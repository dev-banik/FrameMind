using FrameMind.Application.Abstractions;
using FrameMind.Application.Common;
using FrameMind.Domain.Entities;
using FrameMind.Domain.Enums;
using MediatR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace FrameMind.Application.Features.Videos;

/// <summary>Worker-side command: turns an approved script into a rendered, stored MP4.</summary>
public sealed record ProcessGenerationJobCommand(Guid JobId) : IRequest;

public sealed class ProcessGenerationJobHandler(
    IAppDbContext db,
    IScriptGenerator scripts,
    IVoiceGenerator voice,
    ISceneVideoGenerator sceneVideos,
    IVideoAssembler assembler,
    IFileStorage storage,
    IPushNotifier push,
    ILogger<ProcessGenerationJobHandler> logger) : IRequestHandler<ProcessGenerationJobCommand>
{
    /// <summary>Scene clips rendered concurrently; video providers rate-limit aggressively.</summary>
    private const int SceneParallelism = 2;

    public async Task Handle(ProcessGenerationJobCommand request, CancellationToken ct)
    {
        var job = await db.GenerationJobs.Include(j => j.Chat)
            .FirstOrDefaultAsync(j => j.Id == request.JobId, ct);
        if (job?.Chat is null || job.IsFinished)
        {
            logger.LogInformation("Skipping job {JobId}: not found, chat deleted, or already finished", request.JobId);
            return;
        }

        var chat = job.Chat;
        var workDir = Path.Combine(Path.GetTempPath(), "framemind", job.Id.ToString("N"));
        Directory.CreateDirectory(workDir);

        try
        {
            chat.MarkGenerating();
            await Advance(job, GenerationStage.GeneratingScript, 5, ct);
            var script = chat.Script!;
            var prompts = await scripts.BuildScenePromptsAsync(script, chat.Style!.Value, ct);

            // Voiceover, one MP3 per scene so it lines up with the scene cut.
            await Advance(job, GenerationStage.GeneratingVoice, 10, ct);
            var audio = new Dictionary<int, string>();
            var voiced = script.Scenes.Where(s => !string.IsNullOrWhiteSpace(s.SpokenText())).ToList();
            for (var i = 0; i < voiced.Count; i++)
            {
                var scene = voiced[i];
                var path = Path.Combine(workDir, $"voice-{scene.Number:D2}.mp3");
                await voice.SynthesizeAsync(scene.SpokenText(), chat.Language!.Value, chat.VoiceType!.Value, path, ct);
                audio[scene.Number] = path;
                await Advance(job, GenerationStage.GeneratingVoice, 10 + 20 * (i + 1) / voiced.Count, ct);
            }

            // Scene clips.
            await Advance(job, GenerationStage.GeneratingVideo, 30, ct);
            var clips = new Dictionary<int, string>();
            var done = 0;
            using var gate = new SemaphoreSlim(SceneParallelism);
            var progressLock = new SemaphoreSlim(1);
            await Task.WhenAll(prompts.Select(async prompt =>
            {
                await gate.WaitAsync(ct);
                try
                {
                    var path = Path.Combine(workDir, $"scene-{prompt.SceneNumber:D2}.mp4");
                    await sceneVideos.GenerateAsync(prompt, job.Resolution, path, ct);
                    await progressLock.WaitAsync(ct);
                    try
                    {
                        clips[prompt.SceneNumber] = path;
                        done++;
                        await Advance(job, GenerationStage.GeneratingVideo, 30 + 55 * done / prompts.Count, ct);
                    }
                    finally { progressLock.Release(); }
                }
                finally { gate.Release(); }
            }));

            // Subtitles, transitions, voice mix, final encode.
            await Advance(job, GenerationStage.Rendering, 88, ct);
            var assemblyScenes = script.Scenes.Select(s => new AssemblyScene(
                s.Number, clips[s.Number], audio.GetValueOrDefault(s.Number), s.SpokenText(), s.DurationSeconds)).ToList();
            var result = await assembler.AssembleAsync(assemblyScenes, job.Resolution, workDir, ct);

            var videoId = Guid.NewGuid();
            var prefix = $"users/{chat.UserId:N}/chats/{chat.Id:N}/{videoId:N}";
            await storage.UploadAsync($"{prefix}/video.mp4", result.VideoPath, "video/mp4", ct);
            await storage.UploadAsync($"{prefix}/thumb.jpg", result.ThumbnailPath, "image/jpeg", ct);
            await Advance(job, GenerationStage.Rendering, 97, ct);

            var video = new GeneratedVideo(chat.Id, $"{prefix}/video.mp4", $"{prefix}/thumb.jpg", job.Resolution, result.DurationSeconds);
            db.GeneratedVideos.Add(video);
            chat.MarkCompleted(video);
            job.Complete(video.Id);
            await db.SaveChangesAsync(ct);

            await Notify(chat, job, "Your video has been generated.", $"\"{chat.Title}\" is ready. Download now.", "video_ready", ct);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw; // host shutting down: leave the message unacked so it's redelivered
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Generation job {JobId} failed", job.Id);
            job.Fail(ex is ExternalServiceException ? ex.Message : "Video generation failed. Please try again.");
            chat.MarkFailed();
            await db.SaveChangesAsync(CancellationToken.None);
            await Notify(chat, job, "Video generation failed", $"We couldn't finish \"{chat.Title}\". Tap to retry.", "video_failed", CancellationToken.None);
        }
        finally
        {
            try { Directory.Delete(workDir, recursive: true); }
            catch (Exception ex) { logger.LogWarning(ex, "Could not clean work dir {Dir}", workDir); }
        }
    }

    private async Task Advance(GenerationJob job, GenerationStage stage, int progress, CancellationToken ct)
    {
        job.Advance(stage, progress);
        await db.SaveChangesAsync(ct);
    }

    private async Task Notify(Chat chat, GenerationJob job, string title, string body, string type, CancellationToken ct)
    {
        try
        {
            var tokens = await db.DeviceTokens.Where(t => t.UserId == chat.UserId).Select(t => t.Token).ToListAsync(ct);
            if (tokens.Count == 0) return;
            await push.SendAsync(tokens, new PushMessage(title, body, new Dictionary<string, string>
            {
                ["type"] = type,
                ["chatId"] = chat.Id.ToString(),
                ["jobId"] = job.Id.ToString(),
            }), ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Push notification failed for job {JobId}", job.Id);
        }
    }
}
