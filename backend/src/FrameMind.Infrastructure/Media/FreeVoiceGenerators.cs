using FrameMind.Application.Abstractions;
using FrameMind.Application.Common;
using FrameMind.Domain.Enums;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FrameMind.Infrastructure.Media;

/// <summary>
/// Free neural voices through the <c>edge-tts</c> CLI (no API key). It relies on
/// Microsoft's public Edge read-aloud service, so if that call fails the scene falls
/// back to offline eSpeak NG instead of failing the whole video.
/// </summary>
public sealed class EdgeTtsVoiceGenerator(
    ProcessRunner runner, EspeakVoiceGenerator fallback, IOptions<VoiceOptions> options, ILogger<EdgeTtsVoiceGenerator> logger)
    : IVoiceGenerator
{
    private readonly EdgeTtsOptions _opt = options.Value.EdgeTts;

    public async Task SynthesizeAsync(string text, Language language, VoiceType voice, string outputPath, CancellationToken ct)
    {
        var voiceName = _opt.Voices.GetValueOrDefault($"{language}:{voice}")
                        ?? _opt.Voices.GetValueOrDefault($"{language}:Narrator")
                        ?? "en-US-JennyNeural";
        // A higher pitch turns the adult voice into a convincing child voice.
        var (rate, pitch) = voice switch
        {
            VoiceType.Child => ("+5%", "+25Hz"),
            VoiceType.Narrator => ("-5%", "+0Hz"),
            _ => ("+0%", "+0Hz"),
        };

        var textFile = outputPath + ".txt";
        await File.WriteAllTextAsync(textFile, text, ct);
        try
        {
            await runner.RunAsync(_opt.Path,
                ["--voice", voiceName, $"--rate={rate}", $"--pitch={pitch}", "--file", textFile, "--write-media", outputPath],
                TimeSpan.FromMinutes(2), ct);
            if (new FileInfo(outputPath).Length > 0) return;
            throw new ExternalServiceException("edge-tts produced an empty file.");
        }
        catch (ExternalServiceException ex)
        {
            logger.LogWarning(ex, "edge-tts failed for voice {Voice}; falling back to eSpeak NG", voiceName);
            await fallback.SynthesizeAsync(text, language, voice, outputPath, ct);
        }
        finally
        {
            File.Delete(textFile);
        }
    }
}

/// <summary>Offline, robotic-but-free TTS; supports English, Hindi and Bangla.</summary>
public sealed class EspeakVoiceGenerator(ProcessRunner runner, FfmpegTools ffmpeg, IOptions<VoiceOptions> options) : IVoiceGenerator
{
    public async Task SynthesizeAsync(string text, Language language, VoiceType voice, string outputPath, CancellationToken ct)
    {
        var lang = language switch { Language.Bangla => "bn", Language.Hindi => "hi", _ => "en-us" };
        var (variant, pitch) = voice switch
        {
            VoiceType.Female => ("+f3", "55"),
            VoiceType.Child => ("+f4", "85"),
            VoiceType.Male => ("+m3", "45"),
            _ => ("+m1", "40"),
        };

        var textFile = outputPath + ".espeak.txt";
        var wav = outputPath + ".wav";
        await File.WriteAllTextAsync(textFile, text, ct);
        try
        {
            await runner.RunAsync(options.Value.EdgeTts.EspeakPath,
                ["-v", lang + variant, "-p", pitch, "-s", "150", "-f", textFile, "-w", wav], TimeSpan.FromMinutes(1), ct);
            await ffmpeg.FfmpegAsync(["-i", wav, "-c:a", "libmp3lame", "-b:a", "128k", outputPath], ct);
        }
        finally
        {
            File.Delete(textFile);
            File.Delete(wav);
        }
    }
}
