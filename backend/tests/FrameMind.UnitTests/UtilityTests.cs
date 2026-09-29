using System.Text;
using FrameMind.Application.Common;
using FrameMind.Application.Features.Videos;
using FrameMind.Domain.Enums;
using FrameMind.Infrastructure.Media;

namespace FrameMind.UnitTests;

public class UtilityTests
{
    [Theory]
    [InlineData("https://www.youtube.com/watch?v=abc", SourcePlatform.YouTube)]
    [InlineData("https://youtu.be/abc", SourcePlatform.YouTube)]
    [InlineData("https://m.facebook.com/watch/?v=1", SourcePlatform.Facebook)]
    [InlineData("https://www.instagram.com/reel/xyz/", SourcePlatform.Instagram)]
    [InlineData("https://www.tiktok.com/@a/video/1", SourcePlatform.TikTok)]
    [InlineData("https://vimeo.com/123", SourcePlatform.Other)]
    public void Detects_platform(string url, SourcePlatform expected)
    {
        Assert.True(VideoUrl.TryParse(url, out var uri));
        Assert.Equal(expected, VideoUrl.DetectPlatform(uri));
    }

    [Theory]
    [InlineData("")]
    [InlineData("not a url")]
    [InlineData("ftp://youtube.com/x")]
    [InlineData("http://127.0.0.1/video")]
    [InlineData("http://169.254.169.254/latest/meta-data")]
    [InlineData("http://[::1]/x")]
    [InlineData("http://localhost/x")]
    [InlineData("http://db.internal/x")]
    [InlineData("https://user:pass@youtube.com/x")]
    public void Rejects_unsafe_or_invalid_urls(string url) => Assert.False(VideoUrl.TryParse(url, out _));

    [Theory]
    [InlineData("My Great Video!", "my-great-video")]
    [InlineData("   ", "framemind-video")]
    [InlineData("দাদুর ঘুড়ি", "দাদুর-ঘুড়ি")]
    [InlineData("दादी की कहानी", "दादी-की-कहानी")]
    public void Slugifies_file_names(string title, string expected) =>
        Assert.Equal(expected, FileNames.Slug(title));

    [Fact]
    public void Subtitle_cues_cover_the_spoken_window_in_order()
    {
        var srt = new StringBuilder();
        var words = string.Join(' ', Enumerable.Repeat("word", 60)); // ~300 chars → several cues
        var next = FfmpegVideoAssembler.AppendCues(srt, 1, words, 2.0, 12.0);

        var timings = srt.ToString().Split('\n').Select(l => l.Trim()).Where(l => l.Contains("-->")).ToList();
        Assert.True(next > 2);
        Assert.Equal(next - 1, timings.Count);
        Assert.StartsWith("00:00:02,000 -->", timings[0]);
        Assert.EndsWith("--> 00:00:12,000", timings[^1]);
    }

    [Fact]
    public void Subtitle_cues_skip_empty_text() =>
        Assert.Equal(5, FfmpegVideoAssembler.AppendCues(new StringBuilder(), 5, "  ", 0, 10));
}
