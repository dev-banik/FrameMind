using FrameMind.Domain.Common;
using FrameMind.Domain.Enums;

namespace FrameMind.Domain.Entities;

public class GenerationJob : Entity
{
    private GenerationJob() { }

    public GenerationJob(Guid chatId, Resolution resolution)
    {
        ChatId = chatId;
        Resolution = resolution;
        Stage = GenerationStage.Queued;
    }

    public Guid ChatId { get; private set; }
    public Resolution Resolution { get; private set; }
    public GenerationStage Stage { get; private set; }
    public int Progress { get; private set; }
    public string? Error { get; private set; }
    public Guid? VideoId { get; private set; }
    public DateTime? StartedAt { get; private set; }
    public DateTime? CompletedAt { get; private set; }

    public Chat? Chat { get; private set; }

    public bool IsFinished => Stage is GenerationStage.Complete or GenerationStage.Failed;

    public void Advance(GenerationStage stage, int progress)
    {
        if (IsFinished) throw new DomainException("Job has already finished.");
        StartedAt ??= DateTime.UtcNow;
        Stage = stage;
        Progress = Math.Clamp(progress, Progress, 100);
    }

    public void Complete(Guid videoId)
    {
        VideoId = videoId;
        Stage = GenerationStage.Complete;
        Progress = 100;
        CompletedAt = DateTime.UtcNow;
    }

    public void Fail(string error)
    {
        Stage = GenerationStage.Failed;
        Error = error.Length > 1000 ? error[..1000] : error;
        CompletedAt = DateTime.UtcNow;
    }
}

public class GeneratedVideo : Entity
{
    private GeneratedVideo() { }

    public GeneratedVideo(Guid chatId, string storageKey, string? thumbnailKey, Resolution resolution, int durationSeconds)
    {
        ChatId = chatId;
        StorageKey = storageKey;
        ThumbnailKey = thumbnailKey;
        Resolution = resolution;
        DurationSeconds = durationSeconds;
    }

    public Guid ChatId { get; private set; }
    public string StorageKey { get; private set; } = "";
    public string? ThumbnailKey { get; private set; }
    public Resolution Resolution { get; private set; }
    public int DurationSeconds { get; private set; }
}
