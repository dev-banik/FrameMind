using FrameMind.Application.Abstractions;
using FrameMind.Domain.Entities;
using FrameMind.Domain.Enums;
using Microsoft.EntityFrameworkCore;

namespace FrameMind.Worker;

/// <summary>
/// Safety net for jobs whose queue message was lost (publish failed after the DB
/// write) or that hung: re-enqueues never-started jobs and fails runaway ones.
/// </summary>
public sealed class StaleJobSweeper(IServiceScopeFactory scopes, ILogger<StaleJobSweeper> logger) : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan QueuedTimeout = TimeSpan.FromMinutes(15);
    private static readonly TimeSpan RunningTimeout = TimeSpan.FromMinutes(60);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(Interval);
        do
        {
            try { await SweepAsync(stoppingToken); }
            catch (Exception ex) when (ex is not OperationCanceledException) { logger.LogError(ex, "Stale job sweep failed"); }
        }
        while (await timer.WaitForNextTickAsync(stoppingToken));
    }

    private async Task SweepAsync(CancellationToken ct)
    {
        using var scope = scopes.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IAppDbContext>();
        var queue = scope.ServiceProvider.GetRequiredService<IGenerationQueue>();
        var now = DateTime.UtcNow;

        var queuedBefore = now - QueuedTimeout;
        var neverStarted = await db.GenerationJobs.Include(j => j.Chat)
            .Where(j => j.Stage == GenerationStage.Queued && j.StartedAt == null && j.CreatedAt < queuedBefore)
            .Take(50).ToListAsync(ct);
        foreach (var job in neverStarted)
        {
            var plan = await db.Users.Where(u => u.Id == job.Chat!.UserId).Select(u => u.Plan).FirstOrDefaultAsync(ct);
            logger.LogWarning("Re-enqueueing job {JobId} that never started", job.Id);
            await queue.EnqueueAsync(new GenerationJobMessage(job.Id, job.ChatId), PlanPolicy.QueuePriority(plan), ct);
        }

        var runningBefore = now - RunningTimeout;
        var hung = await db.GenerationJobs.Include(j => j.Chat)
            .Where(j => j.StartedAt != null && j.StartedAt < runningBefore
                        && j.Stage != GenerationStage.Complete && j.Stage != GenerationStage.Failed)
            .Take(50).ToListAsync(ct);
        foreach (var job in hung)
        {
            logger.LogWarning("Failing job {JobId} that has been running since {Started}", job.Id, job.StartedAt);
            job.Fail("Video generation took too long. Please try again.");
            job.Chat?.MarkFailed();
        }
        if (hung.Count > 0) await db.SaveChangesAsync(ct);
    }
}
