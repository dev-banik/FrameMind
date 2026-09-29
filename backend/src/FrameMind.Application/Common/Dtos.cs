using FrameMind.Application.Abstractions;
using FrameMind.Domain.Entities;
using FrameMind.Domain.Enums;
using FrameMind.Domain.ValueObjects;

namespace FrameMind.Application.Common;

public sealed record UserProfileDto(
    Guid Id, string Name, string Email, string? PhotoUrl, Plan Plan,
    int VideosGeneratedToday, int? DailyVideoLimit, Resolution MaxResolution);

public sealed record ProjectDto(Guid Id, string Name, int ChatCount, DateTime CreatedAt);

public sealed record ProjectDetailDto(Guid Id, string Name, DateTime CreatedAt, IReadOnlyList<ChatSummaryDto> Chats);

public sealed record ChatSummaryDto(
    Guid Id, Guid? ProjectId, string Title, string? ThumbnailUrl, Language? Language,
    int DurationSeconds, ChatStatus Status, Guid? LatestVideoId, DateTime CreatedAt);

public sealed record GeneratedVideoDto(
    Guid Id, Guid ChatId, Resolution Resolution, int DurationSeconds,
    string? ThumbnailUrl, string StreamUrl, DateTime CreatedAt);

public sealed record GenerationJobDto(
    Guid Id, Guid ChatId, GenerationStage Stage, int Progress, string? Error,
    Guid? VideoId, DateTime CreatedAt, DateTime? CompletedAt);

public sealed record ChatDto(
    Guid Id, Guid? ProjectId, string Title, string? UserPrompt, string VideoUrl,
    Language? Language, int DurationSeconds, VideoStyle? Style, VoiceType? VoiceType,
    ChatStatus Status, VideoAnalysis Analysis, Script? Script,
    IReadOnlyList<GeneratedVideoDto> Videos, GenerationJobDto? ActiveJob,
    DateTime CreatedAt, DateTime UpdatedAt);

public sealed record AnalyzeVideoResult(Guid ChatId, VideoAnalysis Analysis);

public sealed record DownloadLinkDto(string Url, string FileName, DateTime ExpiresAt);

public sealed record PagedResult<T>(IReadOnlyList<T> Items, int Page, int PageSize, int Total);

/// <summary>Maps entities to DTOs, turning storage keys into short-lived signed URLs.</summary>
public sealed class DtoMapper(IFileStorage storage)
{
    public static readonly TimeSpan StreamUrlLifetime = TimeSpan.FromHours(2);

    public GenerationJobDto Job(GenerationJob j) =>
        new(j.Id, j.ChatId, j.Stage, j.Progress, j.Error, j.VideoId, j.CreatedAt, j.CompletedAt);

    public GeneratedVideoDto Video(GeneratedVideo v) => new(
        v.Id, v.ChatId, v.Resolution, v.DurationSeconds,
        v.ThumbnailKey is null ? null : storage.GetSignedUrl(v.ThumbnailKey, StreamUrlLifetime).ToString(),
        storage.GetSignedUrl(v.StorageKey, StreamUrlLifetime).ToString(),
        v.CreatedAt);

    public ChatSummaryDto Summary(Chat c, GeneratedVideo? latest) => new(
        c.Id, c.ProjectId, c.Title,
        latest?.ThumbnailKey is { } key ? storage.GetSignedUrl(key, StreamUrlLifetime).ToString() : c.ThumbnailUrl,
        c.Language, c.Script?.TotalDurationSeconds ?? c.DurationSeconds, c.Status, latest?.Id, c.CreatedAt);

    public ChatDto Chat(Chat c, GenerationJob? activeJob) => new(
        c.Id, c.ProjectId, c.Title, c.UserPrompt, c.VideoUrl, c.Language, c.DurationSeconds,
        c.Style, c.VoiceType, c.Status, c.Analysis, c.Script,
        c.Videos.OrderByDescending(v => v.CreatedAt).Select(Video).ToList(),
        activeJob is null ? null : Job(activeJob),
        c.CreatedAt, c.UpdatedAt);
}
