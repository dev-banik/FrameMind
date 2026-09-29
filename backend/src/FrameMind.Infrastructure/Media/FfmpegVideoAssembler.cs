using System.Text;
using FrameMind.Application.Abstractions;
using FrameMind.Domain.Enums;
using Microsoft.Extensions.Options;

namespace FrameMind.Infrastructure.Media;

/// <summary>
/// Renders the final MP4: each scene clip is normalized to the target resolution at
/// 30 fps and paired with its voiceover, scenes are joined with cross-fades, and
/// subtitles are burned in.
/// </summary>
public sealed class FfmpegVideoAssembler(FfmpegTools ffmpeg, IOptions<MediaOptions> options) : IVideoAssembler
{
    private readonly MediaOptions _opt = options.Value;

    public async Task<AssemblyResult> AssembleAsync(
        IReadOnlyList<AssemblyScene> scenes, Resolution resolution, string workDir, CancellationToken ct)
    {
        if (scenes.Count == 0) throw new ArgumentException("No scenes to assemble.", nameof(scenes));
        var (w, h) = resolution.Dimensions();
        var t = _opt.TransitionSeconds;

        // 1) Normalize each scene into a self-contained segment with audio.
        var segments = new List<(AssemblyScene Scene, string Path, double Duration, double SpeechSeconds)>();
        foreach (var scene in scenes)
        {
            var speech = scene.AudioPath is null ? 0 : await ffmpeg.DurationAsync(scene.AudioPath, ct);
            // Never cut narration off: stretch the scene to fit the voiceover if needed.
            var duration = Math.Max(Math.Max(scene.DurationSeconds, speech + 0.4), t + 0.5);
            var segPath = Path.Combine(workDir, $"seg-{scene.Number:D2}.mp4");

            var args = new List<string> { "-stream_loop", "-1", "-i", scene.VideoPath };
            if (scene.AudioPath is not null) args.AddRange(["-i", scene.AudioPath]);
            else args.AddRange(["-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo"]);
            args.AddRange(
            [
                "-filter_complex",
                $"[0:v]scale={w}:{h}:force_original_aspect_ratio=increase,crop={w}:{h},fps=30,format=yuv420p,setsar=1[v];" +
                "[1:a]aformat=sample_rates=44100:channel_layouts=stereo,apad[a]",
                "-map", "[v]", "-map", "[a]", "-t", Inv.F(duration),
                "-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
                "-c:a", "aac", "-b:a", "192k", segPath,
            ]);
            await ffmpeg.FfmpegAsync(args, ct);
            segments.Add((scene, segPath, duration, speech));
        }

        // 2) Subtitles on the final timeline (each cross-fade overlaps adjacent scenes by t).
        var srt = new StringBuilder();
        var cue = 1;
        var offset = 0.0;
        for (var i = 0; i < segments.Count; i++)
        {
            var (scene, _, duration, speech) = segments[i];
            var visibleEnd = offset + duration - (i < segments.Count - 1 ? t : 0);
            var spokenEnd = speech > 0 ? Math.Min(offset + speech + 0.3, visibleEnd) : visibleEnd;
            cue = AppendCues(srt, cue, scene.SubtitleText, offset + 0.1, spokenEnd);
            offset += duration - t;
        }
        await File.WriteAllTextAsync(Path.Combine(workDir, "subs.srt"), srt.ToString(), new UTF8Encoding(false), ct);

        // 3) Join with cross-fades, burn subtitles, final encode.
        var final = Path.Combine(workDir, "final.mp4");
        var inputs = segments.SelectMany(s => new[] { "-i", Path.GetFileName(s.Path) }).ToList();
        var graph = new StringBuilder();
        string v = "[0:v]", a = "[0:a]";
        var elapsed = segments[0].Duration;
        for (var i = 1; i < segments.Count; i++)
        {
            var xfadeOffset = elapsed - t;
            graph.Append($"{v}[{i}:v]xfade=transition=fade:duration={Inv.F(t)}:offset={Inv.F(xfadeOffset)}[v{i}];");
            graph.Append($"{a}[{i}:a]acrossfade=d={Inv.F(t)}[a{i}];");
            v = $"[v{i}]";
            a = $"[a{i}]";
            elapsed = xfadeOffset + segments[i].Duration;
        }
        var fontSize = resolution == Resolution.P1080 ? 20 : 18;
        graph.Append($"{v}subtitles=subs.srt:force_style='FontName={_opt.SubtitleFont},FontSize={fontSize}," +
                     "PrimaryColour=&H00FFFFFF,OutlineColour=&H99000000,BorderStyle=1,Outline=2,Shadow=0,MarginV=36'[vout]");

        await ffmpeg.FfmpegAsync(
        [
            .. inputs,
            "-filter_complex", graph.ToString(),
            "-map", "[vout]", "-map", a,
            "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-r", "30", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart",
            Path.GetFileName(final),
        ], ct, workDir: workDir, timeout: TimeSpan.FromMinutes(20));

        var total = await ffmpeg.DurationAsync(final, ct);
        var thumb = Path.Combine(workDir, "thumb.jpg");
        await ffmpeg.FfmpegAsync(
            ["-ss", Inv.F(Math.Min(1.5, total / 2)), "-i", final, "-frames:v", "1", "-vf", "scale=640:-2", "-q:v", "3", thumb], ct);

        return new AssemblyResult(final, thumb, (int)Math.Round(total));
    }

    /// <summary>Splits text into ~2-line cues spread over [start, end] proportionally to length.</summary>
    internal static int AppendCues(StringBuilder srt, int cue, string text, double start, double end)
    {
        if (string.IsNullOrWhiteSpace(text) || end - start < 0.3) return cue;

        var chunks = Chunk(text.Trim(), 84);
        var totalChars = chunks.Sum(c => c.Length);
        var cursor = start;
        for (var i = 0; i < chunks.Count; i++)
        {
            // Pin the last cue to `end` so rounding doesn't leave a gap.
            var cueEnd = i == chunks.Count - 1 ? end : cursor + (end - start) * chunks[i].Length / totalChars;
            srt.AppendLine(cue.ToString())
               .AppendLine($"{Ts(cursor)} --> {Ts(cueEnd)}")
               .AppendLine(chunks[i])
               .AppendLine();
            cursor = cueEnd;
            cue++;
        }
        return cue;
    }

    private static List<string> Chunk(string text, int maxChars)
    {
        var chunks = new List<string>();
        var current = new StringBuilder();
        foreach (var word in text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries))
        {
            if (current.Length > 0 && current.Length + word.Length + 1 > maxChars)
            {
                chunks.Add(current.ToString());
                current.Clear();
            }
            if (current.Length > 0) current.Append(' ');
            current.Append(word);
        }
        if (current.Length > 0) chunks.Add(current.ToString());
        return chunks;
    }

    private static string Ts(double seconds)
    {
        var ts = TimeSpan.FromSeconds(Math.Max(0, seconds));
        return $"{(int)ts.TotalHours:00}:{ts.Minutes:00}:{ts.Seconds:00},{ts.Milliseconds:000}";
    }
}
