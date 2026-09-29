using FrameMind.Domain.Enums;

namespace FrameMind.Domain.ValueObjects;

/// <summary>
/// Abstract, non-identifying attributes of a source video. This is the only
/// information about the source that ever reaches script generation.
/// </summary>
public sealed record VideoAnalysis
{
    public string SourceTitle { get; init; } = "";
    public SourcePlatform SourcePlatform { get; init; } = SourcePlatform.Other;
    public string? ThumbnailUrl { get; init; }
    public int SourceDurationSeconds { get; init; }
    public string Category { get; init; } = "";
    public string Theme { get; init; } = "";
    public string Mood { get; init; } = "";
    public string Style { get; init; } = "";
    public IReadOnlyList<string> Characters { get; init; } = [];
    public string Pace { get; init; } = "Medium";
    public string StoryPattern { get; init; } = "";
    public string Summary { get; init; } = "";
}
