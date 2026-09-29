using FluentValidation;
using FrameMind.Application.Abstractions;
using FrameMind.Application.Common;
using FrameMind.Domain.Entities;
using FrameMind.Domain.Enums;
using MediatR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace FrameMind.Application.Features.Chats;

/// <summary>Loads a chat with everything the full <see cref="ChatDto"/> needs.</summary>
public sealed class ChatReader(IAppDbContext db, UserAccessor users, DtoMapper mapper)
{
    public async Task<ChatDto> ReadAsync(Guid chatId, CancellationToken ct)
    {
        var user = await users.GetAsync(ct);
        var chat = await db.Chats.AsNoTracking()
                       .Include(c => c.Videos)
                       .FirstOrDefaultAsync(c => c.Id == chatId && c.UserId == user.Id, ct)
                   ?? throw new NotFoundException("Chat", chatId);

        var activeJob = await db.GenerationJobs.AsNoTracking()
            .Where(j => j.ChatId == chatId)
            .OrderByDescending(j => j.CreatedAt)
            .FirstOrDefaultAsync(ct);

        // Only surface the latest job while it's running or if it failed (so the client can show why).
        if (activeJob is { Stage: GenerationStage.Complete }) activeJob = null;
        return mapper.Chat(chat, activeJob);
    }
}

public sealed record GetChatQuery(Guid Id) : IRequest<ChatDto>;

public sealed class GetChatHandler(ChatReader reader) : IRequestHandler<GetChatQuery, ChatDto>
{
    public Task<ChatDto> Handle(GetChatQuery request, CancellationToken ct) => reader.ReadAsync(request.Id, ct);
}

public sealed record GetHistoryQuery(
    string? Search, Guid? ProjectId, Language? Language, ChatStatus? Status, int Page = 1, int PageSize = 20)
    : IRequest<PagedResult<ChatSummaryDto>>;

public sealed class GetHistoryValidator : AbstractValidator<GetHistoryQuery>
{
    public GetHistoryValidator()
    {
        RuleFor(x => x.Page).GreaterThanOrEqualTo(1);
        RuleFor(x => x.PageSize).InclusiveBetween(1, 100);
        RuleFor(x => x.Search).MaximumLength(200);
    }
}

public sealed class GetHistoryHandler(IAppDbContext db, UserAccessor users, DtoMapper mapper)
    : IRequestHandler<GetHistoryQuery, PagedResult<ChatSummaryDto>>
{
    public async Task<PagedResult<ChatSummaryDto>> Handle(GetHistoryQuery q, CancellationToken ct)
    {
        var user = await users.GetAsync(ct);
        var query = db.Chats.AsNoTracking().Where(c => c.UserId == user.Id);

        if (q.ProjectId is { } projectId) query = query.Where(c => c.ProjectId == projectId);
        if (q.Language is { } language) query = query.Where(c => c.Language == language);
        if (q.Status is { } status) query = query.Where(c => c.Status == status);
        if (!string.IsNullOrWhiteSpace(q.Search))
        {
            var term = q.Search.Trim().ToLower();
            query = query.Where(c => c.Title.ToLower().Contains(term) || c.VideoUrl.ToLower().Contains(term));
        }

        var total = await query.CountAsync(ct);
        var page = await query
            .OrderByDescending(c => c.CreatedAt)
            .Skip((q.Page - 1) * q.PageSize).Take(q.PageSize)
            .Select(c => new { Chat = c, Latest = c.Videos.OrderByDescending(v => v.CreatedAt).FirstOrDefault() })
            .ToListAsync(ct);

        return new PagedResult<ChatSummaryDto>(
            page.Select(x => mapper.Summary(x.Chat, x.Latest)).ToList(), q.Page, q.PageSize, total);
    }
}

public sealed record DuplicateChatCommand(Guid Id) : IRequest<ChatDto>;

public sealed class DuplicateChatHandler(IAppDbContext db, UserAccessor users, ChatReader reader)
    : IRequestHandler<DuplicateChatCommand, ChatDto>
{
    public async Task<ChatDto> Handle(DuplicateChatCommand request, CancellationToken ct)
    {
        var chat = await users.GetOwnedChatAsync(request.Id, ct);
        var copy = chat.Duplicate();
        db.Chats.Add(copy);
        await db.SaveChangesAsync(ct);
        return await reader.ReadAsync(copy.Id, ct);
    }
}

public sealed record MoveChatCommand(Guid Id, Guid? ProjectId) : IRequest;

public sealed class MoveChatHandler(IAppDbContext db, UserAccessor users) : IRequestHandler<MoveChatCommand>
{
    public async Task Handle(MoveChatCommand request, CancellationToken ct)
    {
        var chat = await users.GetOwnedChatAsync(request.Id, ct);
        if (request.ProjectId is { } projectId &&
            !await db.Projects.AnyAsync(p => p.Id == projectId && p.UserId == chat.UserId, ct))
            throw new NotFoundException("Project", projectId);

        chat.MoveToProject(request.ProjectId);
        await db.SaveChangesAsync(ct);
    }
}

public sealed record DeleteChatCommand(Guid Id) : IRequest;

public sealed class DeleteChatHandler(IAppDbContext db, UserAccessor users, IFileStorage storage, ILogger<DeleteChatHandler> logger)
    : IRequestHandler<DeleteChatCommand>
{
    public async Task Handle(DeleteChatCommand request, CancellationToken ct)
    {
        var chat = await users.GetOwnedChatAsync(request.Id, ct, includeVideos: true);
        var keys = chat.Videos.SelectMany(v => new[] { v.StorageKey, v.ThumbnailKey }).OfType<string>().ToList();

        db.Chats.Remove(chat);
        await db.SaveChangesAsync(ct);

        foreach (var key in keys)
        {
            try { await storage.DeleteAsync(key, ct); }
            catch (Exception ex) { logger.LogWarning(ex, "Failed to delete stored object {Key}", key); }
        }
    }
}
