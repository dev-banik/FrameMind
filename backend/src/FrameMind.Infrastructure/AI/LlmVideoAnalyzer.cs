using System.Text;
using System.Text.Json;
using FrameMind.Application.Abstractions;
using FrameMind.Domain.Enums;
using FrameMind.Domain.ValueObjects;
using FrameMind.Infrastructure.Media;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Logging;

namespace FrameMind.Infrastructure.AI;

public sealed class LlmVideoAnalyzer(SourceVideoProbe probe, ILlmJsonClient llm) : IVideoAnalyzer
{
    private const string System = """
        You are a film and social-video analyst. You will receive public metadata and
        evenly spaced keyframes from a short video. Describe only its abstract creative
        attributes so another writer can create a completely different, original video
        in the same genre.

        Rules:
        - Describe category, theme, mood, visual style, pacing and the general story pattern.
        - "characters" lists generic archetypes/roles (e.g. "Father", "Curious child",
          "Street vendor"), never real names, usernames, brands or identifiable people.
        - "summary" describes the format and structure in 1–2 sentences; do not retell
          the plot, quote dialogue, or mention the creator.
        - Write every field in English.
        """;

    private const string Schema = """
        {
          "type": "object",
          "additionalProperties": false,
          "required": ["category", "theme", "mood", "style", "characters", "pace", "storyPattern", "summary"],
          "properties": {
            "category": { "type": "string", "description": "e.g. Family Animation, Motivational Short, Comedy Sketch, Educational Explainer" },
            "theme": { "type": "string" },
            "mood": { "type": "string" },
            "style": { "type": "string", "description": "Visual style, e.g. 3D Animation, Live-action vlog, 2D Cartoon, Cinematic" },
            "characters": { "type": "array", "items": { "type": "string" } },
            "pace": { "type": "string", "enum": ["Slow", "Medium", "Fast"] },
            "storyPattern": { "type": "string", "description": "Abstract beat structure, e.g. Problem -> effort -> warm resolution" },
            "summary": { "type": "string" }
          }
        }
        """;

    private sealed record Result(
        string Category, string Theme, string Mood, string Style, List<string> Characters,
        string Pace, string StoryPattern, string Summary);

    public async Task<VideoAnalysis> AnalyzeAsync(Uri videoUrl, SourcePlatform platform, CancellationToken ct)
    {
        var sample = await probe.SampleAsync(videoUrl, ct);
        var meta = sample.Metadata;
        var frames = EvenlySpaced(sample.Keyframes, llm.MaxImages);

        var text = new StringBuilder()
            .AppendLine($"Platform: {platform}")
            .AppendLine($"Title: {meta.Title}")
            .AppendLine($"Duration: {meta.DurationSeconds} seconds")
            .AppendLine($"Platform categories: {string.Join(", ", meta.Categories)}")
            .AppendLine($"Tags: {string.Join(", ", meta.Tags)}")
            .AppendLine("Description:")
            .AppendLine(meta.Description)
            .AppendLine()
            .AppendLine(frames.Count > 0
                ? $"The {frames.Count} attached image(s) are keyframes in chronological order."
                : "No keyframes could be extracted; rely on the metadata.")
            .ToString();

        var content = new List<LlmPart>();
        content.AddRange(frames.Select(f => new LlmJpeg(f)));
        content.Add(new LlmText(text));

        var r = await llm.CompleteAsync<Result>(System, content, Schema, LlmEffort.Medium, ct);
        return new VideoAnalysis
        {
            SourceTitle = meta.Title,
            SourcePlatform = platform,
            ThumbnailUrl = meta.ThumbnailUrl,
            SourceDurationSeconds = meta.DurationSeconds,
            Category = r.Category,
            Theme = r.Theme,
            Mood = r.Mood,
            Style = r.Style,
            Characters = r.Characters,
            Pace = r.Pace,
            StoryPattern = r.StoryPattern,
            Summary = r.Summary,
        };
    }

    private static List<byte[]> EvenlySpaced(IReadOnlyList<byte[]> frames, int max)
    {
        if (frames.Count <= max) return frames.ToList();
        return Enumerable.Range(0, max).Select(i => frames[i * frames.Count / max]).ToList();
    }
}

/// <summary>Caches analyses per URL in Redis so re-analyzing a popular video is instant.</summary>
public sealed class CachedVideoAnalyzer(LlmVideoAnalyzer inner, IDistributedCache cache, ILogger<CachedVideoAnalyzer> logger)
    : IVideoAnalyzer
{
    private static readonly DistributedCacheEntryOptions Ttl = new() { AbsoluteExpirationRelativeToNow = TimeSpan.FromDays(7) };

    public async Task<VideoAnalysis> AnalyzeAsync(Uri videoUrl, SourcePlatform platform, CancellationToken ct)
    {
        var key = "analysis:v1:" + Convert.ToHexString(
            System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(videoUrl.ToString())));

        try
        {
            var cached = await cache.GetStringAsync(key, ct);
            if (cached is not null)
                return JsonSerializer.Deserialize<VideoAnalysis>(cached, Persistence.AppDbContext.JsonOptions)!;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Analysis cache read failed");
        }

        var analysis = await inner.AnalyzeAsync(videoUrl, platform, ct);

        try
        {
            await cache.SetStringAsync(key, JsonSerializer.Serialize(analysis, Persistence.AppDbContext.JsonOptions), Ttl, ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Analysis cache write failed");
        }
        return analysis;
    }
}
