using System.Net;
using FrameMind.Domain.Enums;

namespace FrameMind.Application.Common;

public static class VideoUrl
{
    private static readonly (string Host, SourcePlatform Platform)[] KnownHosts =
    [
        ("youtube.com", SourcePlatform.YouTube),
        ("youtu.be", SourcePlatform.YouTube),
        ("facebook.com", SourcePlatform.Facebook),
        ("fb.watch", SourcePlatform.Facebook),
        ("instagram.com", SourcePlatform.Instagram),
        ("tiktok.com", SourcePlatform.TikTok),
    ];

    /// <summary>
    /// Accepts only absolute http(s) URLs on public hostnames. IP literals and
    /// local names are rejected so the downloader can't be pointed at internal services.
    /// </summary>
    public static bool TryParse(string? value, out Uri uri)
    {
        uri = null!;
        if (string.IsNullOrWhiteSpace(value) || value.Length > 2048) return false;
        if (!Uri.TryCreate(value.Trim(), UriKind.Absolute, out var parsed)) return false;
        if (parsed.Scheme != Uri.UriSchemeHttps && parsed.Scheme != Uri.UriSchemeHttp) return false;
        if (parsed.HostNameType != UriHostNameType.Dns || IPAddress.TryParse(parsed.Host, out _)) return false;
        if (!parsed.Host.Contains('.') || parsed.Host.EndsWith(".local", StringComparison.OrdinalIgnoreCase)
            || parsed.Host.EndsWith(".internal", StringComparison.OrdinalIgnoreCase)) return false;
        if (!string.IsNullOrEmpty(parsed.UserInfo)) return false;

        uri = parsed;
        return true;
    }

    public static SourcePlatform DetectPlatform(Uri uri)
    {
        var host = uri.Host.ToLowerInvariant();
        foreach (var (known, platform) in KnownHosts)
        {
            if (host == known || host.EndsWith("." + known)) return platform;
        }
        return SourcePlatform.Other;
    }
}
