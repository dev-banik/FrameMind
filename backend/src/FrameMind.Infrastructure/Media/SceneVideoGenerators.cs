using System.Globalization;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FrameMind.Application.Abstractions;
using FrameMind.Application.Common;
using FrameMind.Domain.Enums;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FrameMind.Infrastructure.Media;

/// <summary>
/// Google Veo via the Gemini API long-running <c>predictLongRunning</c> endpoint.
/// Each scene becomes one clip; the assembler loops/trims clips to the scene length.
/// </summary>
public sealed class VeoSceneVideoGenerator(
    IHttpClientFactory httpFactory, IOptions<VideoGenerationOptions> options, ILogger<VeoSceneVideoGenerator> logger)
    : ISceneVideoGenerator
{
    private readonly VeoOptions _opt = options.Value.Veo;

    public async Task GenerateAsync(ScenePrompt prompt, Resolution resolution, string outputPath, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(_opt.ApiKey))
            throw new ExternalServiceException("Video generation is not configured (Google API key missing).");

        var http = httpFactory.CreateClient("veo");
        var baseUrl = _opt.BaseUrl.TrimEnd('/');

        using var start = new HttpRequestMessage(HttpMethod.Post, $"{baseUrl}/models/{_opt.Model}:predictLongRunning")
        {
            Content = JsonContent.Create(new
            {
                instances = new[] { new { prompt = prompt.Prompt } },
                parameters = new
                {
                    aspectRatio = "16:9",
                    resolution = resolution == Resolution.P1080 ? "1080p" : "720p",
                    durationSeconds = _opt.ClipSeconds,
                    negativePrompt = "text, captions, subtitles, watermark, logo, distorted faces, extra limbs",
                },
            }),
        };
        start.Headers.Add("x-goog-api-key", _opt.ApiKey);
        var operation = await SendJsonAsync(http, start, ct);
        var name = operation.GetProperty("name").GetString()!;

        var deadline = DateTime.UtcNow.AddMinutes(_opt.TimeoutMinutes);
        while (true)
        {
            if (operation.TryGetProperty("done", out var done) && done.GetBoolean()) break;
            if (DateTime.UtcNow > deadline) throw new ExternalServiceException("Video generation timed out.");

            await Task.Delay(TimeSpan.FromSeconds(_opt.PollIntervalSeconds), ct);
            using var poll = new HttpRequestMessage(HttpMethod.Get, $"{baseUrl}/{name}");
            poll.Headers.Add("x-goog-api-key", _opt.ApiKey);
            operation = await SendJsonAsync(http, poll, ct);
        }

        if (operation.TryGetProperty("error", out var error))
        {
            logger.LogError("Veo operation {Name} failed: {Error}", name, error.ToString());
            throw new ExternalServiceException($"Scene {prompt.SceneNumber} could not be generated. Try editing its description.");
        }

        var uri = ExtractVideoUri(operation)
                  ?? throw new ExternalServiceException(
                      $"Scene {prompt.SceneNumber} was blocked by the video provider's safety filters. Try editing its description.");

        using var download = new HttpRequestMessage(HttpMethod.Get, uri);
        download.Headers.Add("x-goog-api-key", _opt.ApiKey);
        using var response = await http.SendAsync(download, HttpCompletionOption.ResponseHeadersRead, ct);
        response.EnsureSuccessStatusCode();
        await using var file = File.Create(outputPath);
        await response.Content.CopyToAsync(file, ct);
    }

    private static string? ExtractVideoUri(JsonElement operation)
    {
        if (!operation.TryGetProperty("response", out var response)) return null;
        if (!response.TryGetProperty("generateVideoResponse", out var gvr)) return null;
        if (!gvr.TryGetProperty("generatedSamples", out var samples) || samples.GetArrayLength() == 0) return null;
        return samples[0].TryGetProperty("video", out var video) && video.TryGetProperty("uri", out var uri)
            ? uri.GetString() : null;
    }

    private async Task<JsonElement> SendJsonAsync(HttpClient http, HttpRequestMessage request, CancellationToken ct)
    {
        using var response = await http.SendAsync(request, ct);
        var body = await response.Content.ReadAsStringAsync(ct);
        if (!response.IsSuccessStatusCode)
        {
            logger.LogError("Veo returned {Status}: {Body}", (int)response.StatusCode, body.Length > 500 ? body[..500] : body);
            throw new ExternalServiceException(response.StatusCode == HttpStatusCode.TooManyRequests
                ? "The video service is busy. Please retry shortly."
                : "The video service returned an error.");
        }
        using var doc = JsonDocument.Parse(body);
        return doc.RootElement.Clone();
    }
}

/// <summary>
/// Development stand-in that renders an animated title card per scene, so the
/// full pipeline (voice → scenes → transitions → subtitles → MP4) runs without API keys.
/// </summary>
public sealed class PlaceholderSceneVideoGenerator(FfmpegTools ffmpeg) : ISceneVideoGenerator
{
    private static readonly string[] Palette = ["0x4F46E5", "0x7C3AED", "0x0EA5E9", "0x059669", "0xD97706", "0xDB2777"];

    public async Task GenerateAsync(ScenePrompt prompt, Resolution resolution, string outputPath, CancellationToken ct)
    {
        var (w, h) = resolution.Dimensions();
        var color = Palette[(prompt.SceneNumber - 1) % Palette.Length];
        var dir = Path.GetDirectoryName(outputPath)!;
        var textFile = Path.Combine(dir, $"card-{prompt.SceneNumber:D2}.txt");
        await File.WriteAllTextAsync(textFile, $"Scene {prompt.SceneNumber}\n\n{Wrap(prompt.Prompt, 60, 6)}", ct);

        var fontSize = h / 28;
        await ffmpeg.FfmpegAsync(
        [
            "-f", "lavfi", "-i", $"color=c={color}:s={w}x{h}:r=30:d={prompt.DurationSeconds}",
            "-vf", $"hue=h=t*12,drawtext=textfile={Path.GetFileName(textFile)}:fontcolor=white:fontsize={fontSize}" +
                   ":line_spacing=8:x=(w-text_w)/2:y=(h-text_h)/2:box=1:boxcolor=black@0.35:boxborderw=24",
            "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p", "-an",
            Path.GetFileName(outputPath),
        ], ct, workDir: dir);
    }

    private static string Wrap(string text, int width, int maxLines)
    {
        var lines = new List<string>();
        var line = "";
        foreach (var word in text.Split(' ', StringSplitOptions.RemoveEmptyEntries))
        {
            if (line.Length + word.Length + 1 > width)
            {
                lines.Add(line);
                line = "";
                if (lines.Count == maxLines) break;
            }
            line = line.Length == 0 ? word : $"{line} {word}";
        }
        if (lines.Count < maxLines && line.Length > 0) lines.Add(line);
        // drawtext treats % and \ specially even in text files.
        return string.Join('\n', lines).Replace("\\", "").Replace("%", "%%");
    }
}

internal static class Inv
{
    public static string F(double v) => v.ToString("0.###", CultureInfo.InvariantCulture);
}
