using FrameMind.Domain.Common;
using FrameMind.Domain.Enums;
using FrameMind.Domain.ValueObjects;

namespace FrameMind.Domain.Entities;

/// <summary>
/// One generation conversation: source video → analysis → script → video(s).
/// </summary>
public class Chat : Entity
{
    private Chat() { }

    public Chat(Guid userId, Guid? projectId, string videoUrl, string? userPrompt, VideoAnalysis analysis)
    {
        UserId = userId;
        ProjectId = projectId;
        VideoUrl = videoUrl;
        UserPrompt = userPrompt;
        Analysis = analysis;
        Title = string.IsNullOrWhiteSpace(analysis.Category) ? "New video" : $"{analysis.Category} idea";
        ThumbnailUrl = analysis.ThumbnailUrl;
        Status = ChatStatus.Analyzed;
        UpdatedAt = CreatedAt;
    }

    public Guid UserId { get; private set; }
    public Guid? ProjectId { get; private set; }
    public string Title { get; private set; } = "";
    public string? UserPrompt { get; private set; }
    public string VideoUrl { get; private set; } = "";
    public string? ThumbnailUrl { get; private set; }
    public Language? Language { get; private set; }
    public int DurationSeconds { get; private set; }
    public VideoStyle? Style { get; private set; }
    public VoiceType? VoiceType { get; private set; }
    public VideoAnalysis Analysis { get; private set; } = new();
    public Script? Script { get; private set; }
    public ChatStatus Status { get; private set; }
    public DateTime UpdatedAt { get; private set; }

    public Project? Project { get; private set; }
    public ICollection<GeneratedVideo> Videos { get; private set; } = new List<GeneratedVideo>();
    public ICollection<GenerationJob> Jobs { get; private set; } = new List<GenerationJob>();

    public bool IsGenerating => Status is ChatStatus.Queued or ChatStatus.Generating;

    public void Configure(Language language, int durationSeconds, VideoStyle style, VoiceType voiceType, string? userPrompt)
    {
        EnsureNotGenerating();
        Language = language;
        DurationSeconds = durationSeconds;
        Style = style;
        VoiceType = voiceType;
        if (!string.IsNullOrWhiteSpace(userPrompt)) UserPrompt = userPrompt.Trim();
        Touch();
    }

    public void SetScript(Script script)
    {
        EnsureNotGenerating();
        if (script.Scenes.Count == 0) throw new DomainException("A script needs at least one scene.");
        Script = script.Renumbered();
        if (!string.IsNullOrWhiteSpace(script.Title)) Title = script.Title.Trim();
        if (Status is ChatStatus.Analyzed or ChatStatus.Failed) Status = ChatStatus.ScriptReady;
        Touch();
    }

    public GenerationJob QueueGeneration(Resolution resolution)
    {
        EnsureNotGenerating();
        if (Script is null || Language is null || Style is null || VoiceType is null)
            throw new DomainException("Generate and approve a script before generating a video.");

        var job = new GenerationJob(Id, resolution);
        Jobs.Add(job);
        Status = ChatStatus.Queued;
        Touch();
        return job;
    }

    public void MarkGenerating() { Status = ChatStatus.Generating; Touch(); }

    public void MarkCompleted(GeneratedVideo video)
    {
        Videos.Add(video);
        Status = ChatStatus.Completed;
        Touch();
    }

    public void MarkFailed() { Status = ChatStatus.Failed; Touch(); }

    public void MoveToProject(Guid? projectId) { ProjectId = projectId; Touch(); }

    public Chat Duplicate()
    {
        var copy = new Chat(UserId, ProjectId, VideoUrl, UserPrompt, Analysis)
        {
            Title = $"{Title} (copy)",
            Language = Language,
            DurationSeconds = DurationSeconds,
            Style = Style,
            VoiceType = VoiceType,
            Script = Script,
            ThumbnailUrl = Analysis.ThumbnailUrl,
        };
        copy.Status = Script is null ? ChatStatus.Analyzed : ChatStatus.ScriptReady;
        return copy;
    }

    private void EnsureNotGenerating()
    {
        if (IsGenerating) throw new DomainException("A video is currently being generated for this chat.");
    }

    private void Touch() => UpdatedAt = DateTime.UtcNow;
}
