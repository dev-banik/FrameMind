using System.Security.Cryptography;
using System.Text;
using FrameMind.Application.Abstractions;
using FrameMind.Domain.Enums;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FrameMind.Infrastructure.Media;

/// <summary>
/// Free video mode: one AI illustration per scene from a keyless text-to-image
/// service, animated with a slow Ken Burns move (zoom in, zoom out or pan). If the
/// image service is unavailable the scene falls back to a title card so the video
/// still renders.
/// </summary>
public sealed class StoryboardSceneVideoGenerator(
    IHttpClientFactory httpFactory, FfmpegTools ffmpeg, PlaceholderSceneVideoGenerator fallback,
    IOptions<VideoGenerationOptions> options, ILogger<StoryboardSceneVideoGenerator> logger) : ISceneVideoGenerator
{
    // The anonymous image tier allows one request at a time; share the gate across jobs.
    private static readonly SemaphoreSlim Gate = new(1, 1);
    private static DateTime _lastRequest = DateTime.MinValue;

    private readonly StoryboardOptions _opt = options.Value.Storyboard;

    public async Task GenerateAsync(ScenePrompt prompt, Resolution resolution, string outputPath, CancellationToken ct)
    {
        var (w, h) = resolution.Dimensions();
        var dir = Path.GetDirectoryName(outputPath)!;
        var image = Path.Combine(dir, $"image-{prompt.SceneNumber:D2}.jpg");

        if (!await TryDownloadImageAsync(prompt, w, h, JobSeed(dir), image, ct))
        {
            await fallback.GenerateAsync(prompt, resolution, outputPath, ct);
            return;
        }

        var frames = Math.Max(30, prompt.DurationSeconds * 30);
        var motion = (prompt.SceneNumber % 3) switch
        {
            1 => $"z='min(1+0.15*on/{frames},1.15)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'",   // push in
            2 => $"z='1.15-0.15*on/{frames}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'",          // pull out
            _ => $"z='1.12':x='(iw-iw/zoom)*on/{frames}':y='ih/2-(ih/zoom/2)'",                    // pan right
        };

        await ffmpeg.FfmpegAsync(
        [
            "-i", image,
            // Upscale first so the slow zoom doesn't jitter on whole-pixel steps.
            "-vf", $"scale={w * 2}:{h * 2}:force_original_aspect_ratio=increase,crop={w * 2}:{h * 2}," +
                   $"zoompan={motion}:d={frames}:s={w}x{h}:fps=30,format=yuv420p",
            "-frames:v", frames.ToString(), "-c:v", "libx264", "-preset", "veryfast", "-an", outputPath,
        ], ct);
    }

    private async Task<bool> TryDownloadImageAsync(ScenePrompt prompt, int w, int h, int seed, string path, CancellationToken ct)
    {
        // Keep URLs a sane length; the style and characters come first in the prompt.
        var text = prompt.Prompt.Length > 900 ? prompt.Prompt[..900] : prompt.Prompt;
        var url = _opt.ImageUrlTemplate
            .Replace("{prompt}", Uri.EscapeDataString(text))
            .Replace("{width}", w.ToString())
            .Replace("{height}", h.ToString())
            .Replace("{seed}", seed.ToString());

        var http = httpFactory.CreateClient("images");
        for (var attempt = 1; attempt <= _opt.Retries; attempt++)
        {
            await Gate.WaitAsync(ct);
            try
            {
                var wait = _lastRequest.AddSeconds(_opt.MinSecondsBetweenRequests) - DateTime.UtcNow;
                if (wait > TimeSpan.Zero) await Task.Delay(wait, ct);

                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
                timeout.CancelAfter(TimeSpan.FromSeconds(_opt.RequestTimeoutSeconds));
                using var response = await http.GetAsync(url, timeout.Token);
                _lastRequest = DateTime.UtcNow;

                var bytes = await response.Content.ReadAsByteArrayAsync(timeout.Token);
                var isImage = response.Content.Headers.ContentType?.MediaType?.StartsWith("image/") == true;
                if (response.IsSuccessStatusCode && isImage && bytes.Length > 5_000)
                {
                    await File.WriteAllBytesAsync(path, bytes, ct);
                    return true;
                }
                logger.LogWarning("Image request for scene {Scene} returned {Status} ({Type}, {Bytes} bytes), attempt {Attempt}",
                    prompt.SceneNumber, (int)response.StatusCode, response.Content.Headers.ContentType?.MediaType, bytes.Length, attempt);
            }
            catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException && !ct.IsCancellationRequested)
            {
                _lastRequest = DateTime.UtcNow;
                logger.LogWarning(ex, "Image request for scene {Scene} failed, attempt {Attempt}", prompt.SceneNumber, attempt);
            }
            finally
            {
                Gate.Release();
            }
            await Task.Delay(TimeSpan.FromSeconds(5 * attempt), ct);
        }

        logger.LogWarning("Using a title card for scene {Scene}: image service unavailable", prompt.SceneNumber);
        return false;
    }

    /// <summary>Same seed for every scene of a job (its work dir) keeps the look consistent.</summary>
    private static int JobSeed(string workDir) =>
        BitConverter.ToInt32(SHA256.HashData(Encoding.UTF8.GetBytes(workDir))) & 0x7FFFFFFF;
}
