using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using FrameMind.Application.Common;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FrameMind.Infrastructure.Media;

public sealed record SourceMetadata(
    string Title, string Description, IReadOnlyList<string> Tags, IReadOnlyList<string> Categories,
    int DurationSeconds, string? ThumbnailUrl);

public sealed record SourceSample(SourceMetadata Metadata, IReadOnlyList<byte[]> Keyframes);

/// <summary>
/// Fetches public metadata with yt-dlp and samples evenly spaced keyframes from a
/// low-resolution copy. The downloaded file is only used transiently for sampling.
/// </summary>
public sealed class SourceVideoProbe(
    ProcessRunner runner, FfmpegTools ffmpeg, IHttpClientFactory httpFactory,
    IOptions<MediaOptions> options, ILogger<SourceVideoProbe> logger)
{
    private readonly MediaOptions _opt = options.Value;

    public async Task<SourceSample> SampleAsync(Uri url, CancellationToken ct)
    {
        await EnsurePublicHostAsync(url, ct);

        var metadata = await ReadMetadataAsync(url, ct);
        if (metadata.DurationSeconds > _opt.MaxSourceDurationSeconds)
            throw new FluentValidation.ValidationException(
                $"Videos longer than {_opt.MaxSourceDurationSeconds / 60} minutes aren't supported yet.");

        var workDir = Path.Combine(Path.GetTempPath(), "framemind", "probe-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(workDir);
        try
        {
            var frames = await TryExtractKeyframesAsync(url, metadata, workDir, ct);
            if (frames.Count == 0 && metadata.ThumbnailUrl is not null)
            {
                // Some platforms block anonymous downloads; the thumbnail still carries the visual style.
                var thumb = await TryDownloadThumbnailAsync(metadata.ThumbnailUrl, workDir, ct);
                if (thumb is not null) frames = [thumb];
            }
            return new SourceSample(metadata, frames);
        }
        finally
        {
            try { Directory.Delete(workDir, true); } catch { /* best effort */ }
        }
    }

    private async Task<SourceMetadata> ReadMetadataAsync(Uri url, CancellationToken ct)
    {
        ProcessResult result;
        try
        {
            result = await runner.RunAsync(_opt.YtDlpPath,
                ["--dump-single-json", "--no-playlist", "--skip-download", "--no-warnings", "--", url.ToString()],
                TimeSpan.FromSeconds(60), ct);
        }
        catch (ExternalServiceException ex)
        {
            throw new ExternalServiceException(
                "We couldn't read that video. Make sure it's public and the link is correct.", ex);
        }

        using var doc = JsonDocument.Parse(result.StdOut);
        var root = doc.RootElement;
        return new SourceMetadata(
            Str(root, "title") ?? "Untitled video",
            Truncate(Str(root, "description") ?? "", 1500),
            StrArray(root, "tags").Take(20).ToList(),
            StrArray(root, "categories").ToList(),
            root.TryGetProperty("duration", out var d) && d.ValueKind == JsonValueKind.Number ? (int)Math.Round(d.GetDouble()) : 0,
            Str(root, "thumbnail"));
    }

    private async Task<List<byte[]>> TryExtractKeyframesAsync(Uri url, SourceMetadata meta, string workDir, CancellationToken ct)
    {
        var source = Path.Combine(workDir, "source.mp4");
        try
        {
            await runner.RunAsync(_opt.YtDlpPath,
            [
                "--no-playlist", "--no-warnings", "--quiet",
                "-f", "worst[ext=mp4][height>=240]/worst[ext=mp4]/worst",
                "--max-filesize", $"{_opt.MaxDownloadMegabytes}M",
                "-o", source, "--", url.ToString(),
            ], TimeSpan.FromMinutes(3), ct);

            if (!File.Exists(source)) return [];

            var duration = meta.DurationSeconds > 0 ? meta.DurationSeconds : await ffmpeg.DurationAsync(source, ct);
            var count = Math.Max(1, _opt.KeyframeCount);
            var fps = duration > 0 ? (count / duration).ToString("0.#####", CultureInfo.InvariantCulture) : "1";
            await ffmpeg.FfmpegAsync(
                ["-i", source, "-vf", $"fps={fps},scale=512:-2", "-frames:v", count.ToString(), "-q:v", "4",
                 Path.Combine(workDir, "frame-%02d.jpg")], ct, timeout: TimeSpan.FromMinutes(2));

            return Directory.GetFiles(workDir, "frame-*.jpg").Order().Select(File.ReadAllBytes).ToList();
        }
        catch (ExternalServiceException ex)
        {
            logger.LogWarning(ex, "Keyframe extraction failed for {Url}; falling back to metadata only", url);
            return [];
        }
    }

    private async Task<byte[]?> TryDownloadThumbnailAsync(string thumbnailUrl, string workDir, CancellationToken ct)
    {
        try
        {
            if (!Uri.TryCreate(thumbnailUrl, UriKind.Absolute, out var uri)) return null;
            await EnsurePublicHostAsync(uri, ct);
            var raw = Path.Combine(workDir, "thumb-src");
            await File.WriteAllBytesAsync(raw, await httpFactory.CreateClient("media").GetByteArrayAsync(uri, ct), ct);
            // Normalize to JPEG (thumbnails are often WebP).
            var jpg = Path.Combine(workDir, "thumb.jpg");
            await ffmpeg.FfmpegAsync(["-i", raw, "-vf", "scale=512:-2", "-frames:v", "1", jpg], ct);
            return await File.ReadAllBytesAsync(jpg, ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Thumbnail download failed");
            return null;
        }
    }

    /// <summary>Blocks URLs whose host resolves to loopback, private or link-local addresses (SSRF guard).</summary>
    private static async Task EnsurePublicHostAsync(Uri url, CancellationToken ct)
    {
        IPAddress[] addresses;
        try { addresses = await Dns.GetHostAddressesAsync(url.Host, ct); }
        catch (SocketException) { throw new FluentValidation.ValidationException("That link's website could not be found."); }

        if (addresses.Length == 0 || addresses.Any(IsNonPublic))
            throw new FluentValidation.ValidationException("Only public video links are supported.");
    }

    private static bool IsNonPublic(IPAddress ip)
    {
        if (ip.IsIPv4MappedToIPv6) ip = ip.MapToIPv4();
        if (IPAddress.IsLoopback(ip) || ip.IsIPv6LinkLocal || ip.IsIPv6SiteLocal || ip.IsIPv6UniqueLocal) return true;
        if (ip.AddressFamily != AddressFamily.InterNetwork) return false;
        var b = ip.GetAddressBytes();
        return b[0] switch
        {
            0 or 10 or 127 => true,
            100 => b[1] >= 64 && b[1] <= 127,  // CGNAT
            169 => b[1] == 254,                // link-local / cloud metadata
            172 => b[1] >= 16 && b[1] <= 31,
            192 => b[1] == 168,
            _ => b[0] >= 224,                  // multicast / reserved
        };
    }

    private static string? Str(JsonElement e, string name) =>
        e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    private static IEnumerable<string> StrArray(JsonElement e, string name) =>
        e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Array
            ? v.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.String).Select(x => x.GetString()!)
            : [];

    private static string Truncate(string s, int max) => s.Length <= max ? s : s[..max];
}
