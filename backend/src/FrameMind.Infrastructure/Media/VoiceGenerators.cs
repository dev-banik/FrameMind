using System.Globalization;
using System.Net;
using System.Net.Http.Json;
using FrameMind.Application.Abstractions;
using FrameMind.Application.Common;
using FrameMind.Domain.Enums;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FrameMind.Infrastructure.Media;

/// <summary>ElevenLabs text-to-speech (English, Hindi, Bangla).</summary>
public sealed class ElevenLabsVoiceGenerator(
    IHttpClientFactory httpFactory, IOptions<VoiceOptions> options, ILogger<ElevenLabsVoiceGenerator> logger) : IVoiceGenerator
{
    private readonly ElevenLabsOptions _opt = options.Value.ElevenLabs;

    public async Task SynthesizeAsync(string text, Language language, VoiceType voice, string outputPath, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(_opt.ApiKey))
            throw new ExternalServiceException("Voice generation is not configured (ElevenLabs API key missing).");

        var voiceId = _opt.Voices.GetValueOrDefault(voice) ?? _opt.Voices[VoiceType.Narrator];
        var model = _opt.Models.GetValueOrDefault(language) ?? "eleven_multilingual_v2";

        using var request = new HttpRequestMessage(HttpMethod.Post,
            $"{_opt.BaseUrl.TrimEnd('/')}/text-to-speech/{Uri.EscapeDataString(voiceId)}?output_format={_opt.OutputFormat}");
        request.Headers.Add("xi-api-key", _opt.ApiKey);
        request.Content = JsonContent.Create(new { text, model_id = model });

        using var response = await httpFactory.CreateClient("elevenlabs").SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync(ct);
            logger.LogError("ElevenLabs returned {Status}: {Body}", (int)response.StatusCode, body.Length > 500 ? body[..500] : body);
            throw new ExternalServiceException(response.StatusCode == HttpStatusCode.TooManyRequests
                ? "The voice service is busy. Please retry shortly."
                : "Voice generation failed.");
        }

        await using var file = File.Create(outputPath);
        await response.Content.CopyToAsync(file, ct);
    }
}

/// <summary>Development stand-in: silent audio sized to how long the text takes to read.</summary>
public sealed class PlaceholderVoiceGenerator(FfmpegTools ffmpeg) : IVoiceGenerator
{
    public async Task SynthesizeAsync(string text, Language language, VoiceType voice, string outputPath, CancellationToken ct)
    {
        var words = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;
        var seconds = Math.Max(1.0, words / 2.5);
        await ffmpeg.FfmpegAsync(
            ["-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", seconds.ToString("0.##", CultureInfo.InvariantCulture),
             "-c:a", "libmp3lame", "-b:a", "64k", outputPath], ct);
    }
}
