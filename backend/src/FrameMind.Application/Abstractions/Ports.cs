using FrameMind.Domain.Entities;
using FrameMind.Domain.Enums;
using FrameMind.Domain.ValueObjects;
using Microsoft.EntityFrameworkCore;

namespace FrameMind.Application.Abstractions;

public interface IAppDbContext
{
    DbSet<User> Users { get; }
    DbSet<DeviceToken> DeviceTokens { get; }
    DbSet<Project> Projects { get; }
    DbSet<Chat> Chats { get; }
    DbSet<GenerationJob> GenerationJobs { get; }
    DbSet<GeneratedVideo> GeneratedVideos { get; }

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}

/// <summary>Identity of the caller, taken from the validated Firebase token.</summary>
public interface ICurrentUser
{
    string FirebaseUid { get; }
    string? Name { get; }
    string? Email { get; }
    string? PhotoUrl { get; }
}

/// <summary>Extracts abstract style attributes from a public video.</summary>
public interface IVideoAnalyzer
{
    Task<VideoAnalysis> AnalyzeAsync(Uri videoUrl, SourcePlatform platform, CancellationToken ct);
}

public sealed record ScriptRequest(
    VideoAnalysis Inspiration,
    Language Language,
    int DurationSeconds,
    VideoStyle Style,
    VoiceType VoiceType,
    string? UserPrompt);

public interface IScriptGenerator
{
    Task<Script> GenerateAsync(ScriptRequest request, CancellationToken ct);

    Task<Scene> RegenerateSceneAsync(ScriptRequest request, Script script, int sceneNumber, string? instructions, CancellationToken ct);

    Task<Script> RegenerateScriptAsync(ScriptRequest request, Script previous, string? instructions, CancellationToken ct);

    /// <summary>Turns scenes into visual prompts for the video model (scene + character consistency).</summary>
    Task<IReadOnlyList<ScenePrompt>> BuildScenePromptsAsync(Script script, VideoStyle style, CancellationToken ct);
}

public sealed record ScenePrompt(int SceneNumber, string Prompt, int DurationSeconds);

public sealed record GenerationJobMessage(Guid JobId, Guid ChatId);

public interface IGenerationQueue
{
    Task EnqueueAsync(GenerationJobMessage message, byte priority, CancellationToken ct);
}

public interface IFileStorage
{
    Task UploadAsync(string key, string localPath, string contentType, CancellationToken ct);
    Task DeleteAsync(string key, CancellationToken ct);
    Uri GetSignedUrl(string key, TimeSpan lifetime, string? downloadFileName = null);
}

public interface IVoiceGenerator
{
    /// <summary>Synthesizes <paramref name="text"/> to an MP3 file at <paramref name="outputPath"/>.</summary>
    Task SynthesizeAsync(string text, Language language, VoiceType voice, string outputPath, CancellationToken ct);
}

public interface ISceneVideoGenerator
{
    /// <summary>Generates a silent clip for one scene and writes it to <paramref name="outputPath"/>.</summary>
    Task GenerateAsync(ScenePrompt prompt, Resolution resolution, string outputPath, CancellationToken ct);
}

public sealed record AssemblyScene(int Number, string VideoPath, string? AudioPath, string SubtitleText, int DurationSeconds);

public sealed record AssemblyResult(string VideoPath, string ThumbnailPath, int DurationSeconds);

public interface IVideoAssembler
{
    /// <summary>Normalizes scenes, adds transitions, voiceover and burned-in subtitles, renders MP4 (H.264, 30 fps).</summary>
    Task<AssemblyResult> AssembleAsync(IReadOnlyList<AssemblyScene> scenes, Resolution resolution, string workDir, CancellationToken ct);
}

public sealed record PushMessage(string Title, string Body, IReadOnlyDictionary<string, string> Data);

public interface IPushNotifier
{
    Task SendAsync(IReadOnlyCollection<string> deviceTokens, PushMessage message, CancellationToken ct);
}
