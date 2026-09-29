using FluentValidation;
using FrameMind.Application.Abstractions;
using FrameMind.Application.Common;
using FrameMind.Domain.Entities;
using FrameMind.Domain.Enums;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace FrameMind.Application.Features.Videos;

public sealed record GenerateVideoCommand(Guid ChatId, Resolution Resolution) : IRequest<GenerationJobDto>;

public sealed class GenerateVideoValidator : AbstractValidator<GenerateVideoCommand>
{
    public GenerateVideoValidator() => RuleFor(x => x.Resolution).IsInEnum();
}

public sealed class GenerateVideoHandler(
    IAppDbContext db, UserAccessor users, IGenerationQueue queue, DtoMapper mapper)
    : IRequestHandler<GenerateVideoCommand, GenerationJobDto>
{
    public async Task<GenerationJobDto> Handle(GenerateVideoCommand request, CancellationToken ct)
    {
        var user = await users.GetAsync(ct);
        if (!PlanPolicy.Allows(user.Plan, request.Resolution))
            throw new PlanLimitException($"{request.Resolution.Label()} requires the Premium plan.");

        if (PlanPolicy.DailyVideoLimit(user.Plan) is { } limit &&
            await users.CountVideosTodayAsync(user.Id, ct) >= limit)
            throw new QuotaExceededException($"The Free plan includes {limit} videos per day. Upgrade to Premium for unlimited videos.");

        var chat = await users.GetOwnedChatAsync(request.ChatId, ct);
        var job = chat.QueueGeneration(request.Resolution);
        db.GenerationJobs.Add(job);
        await db.SaveChangesAsync(ct);

        await queue.EnqueueAsync(new GenerationJobMessage(job.Id, chat.Id), PlanPolicy.QueuePriority(user.Plan), ct);
        return mapper.Job(job);
    }
}

public sealed record GetJobQuery(Guid JobId) : IRequest<GenerationJobDto>;

public sealed class GetJobHandler(IAppDbContext db, UserAccessor users, DtoMapper mapper)
    : IRequestHandler<GetJobQuery, GenerationJobDto>
{
    public async Task<GenerationJobDto> Handle(GetJobQuery request, CancellationToken ct)
    {
        var user = await users.GetAsync(ct);
        var job = await db.GenerationJobs.AsNoTracking()
                      .FirstOrDefaultAsync(j => j.Id == request.JobId && j.Chat!.UserId == user.Id, ct)
                  ?? throw new NotFoundException("Job", request.JobId);
        return mapper.Job(job);
    }
}

public sealed record GetDownloadLinkQuery(Guid VideoId) : IRequest<DownloadLinkDto>;

public sealed class GetDownloadLinkHandler(IAppDbContext db, UserAccessor users, IFileStorage storage)
    : IRequestHandler<GetDownloadLinkQuery, DownloadLinkDto>
{
    private static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(15);

    public async Task<DownloadLinkDto> Handle(GetDownloadLinkQuery request, CancellationToken ct)
    {
        var user = await users.GetAsync(ct);
        var video = await db.GeneratedVideos.AsNoTracking()
                        .Where(v => v.Id == request.VideoId)
                        .Join(db.Chats.Where(c => c.UserId == user.Id), v => v.ChatId, c => c.Id,
                            (v, c) => new { v.StorageKey, v.Resolution, c.Title })
                        .FirstOrDefaultAsync(ct)
                    ?? throw new NotFoundException("Video", request.VideoId);

        var fileName = $"{FileNames.Slug(video.Title)}-{video.Resolution.Label()}.mp4";
        var url = storage.GetSignedUrl(video.StorageKey, Lifetime, fileName);
        return new DownloadLinkDto(url.ToString(), fileName, DateTime.UtcNow.Add(Lifetime));
    }
}

public static class FileNames
{
    public static string Slug(string title)
    {
        var chars = title.Trim().ToLowerInvariant()
            // Keep combining marks so Bangla/Hindi vowel signs survive.
            .Select(ch => char.IsLetterOrDigit(ch)
                          || char.GetUnicodeCategory(ch) is System.Globalization.UnicodeCategory.NonSpacingMark
                              or System.Globalization.UnicodeCategory.SpacingCombiningMark ? ch : '-')
            .ToArray();
        var slug = string.Join('-', new string(chars).Split('-', StringSplitOptions.RemoveEmptyEntries));
        if (slug.Length > 60) slug = slug[..60].TrimEnd('-');
        return slug.Length == 0 ? "framemind-video" : slug;
    }
}
