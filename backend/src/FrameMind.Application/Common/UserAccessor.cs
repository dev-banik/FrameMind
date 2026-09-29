using FrameMind.Application.Abstractions;
using FrameMind.Domain.Entities;
using FrameMind.Domain.Enums;
using Microsoft.EntityFrameworkCore;

namespace FrameMind.Application.Common;

/// <summary>Resolves (and on first sight provisions) the database user for the current token.</summary>
public sealed class UserAccessor(IAppDbContext db, ICurrentUser currentUser)
{
    private User? _cached;

    public async Task<User> GetAsync(CancellationToken ct)
    {
        if (_cached is not null) return _cached;

        var user = await db.Users.FirstOrDefaultAsync(u => u.FirebaseUid == currentUser.FirebaseUid, ct);
        var name = currentUser.Name ?? currentUser.Email?.Split('@')[0] ?? "Creator";
        var email = currentUser.Email ?? "";

        if (user is null)
        {
            user = new User(currentUser.FirebaseUid, name, email, currentUser.PhotoUrl);
            db.Users.Add(user);
            await db.SaveChangesAsync(ct);
        }
        else if (user.Name != name || user.Email != email || user.PhotoUrl != currentUser.PhotoUrl)
        {
            user.UpdateProfile(name, email, currentUser.PhotoUrl);
            await db.SaveChangesAsync(ct);
        }

        return _cached = user;
    }

    public async Task<Chat> GetOwnedChatAsync(Guid chatId, CancellationToken ct, bool includeVideos = false)
    {
        var user = await GetAsync(ct);
        IQueryable<Chat> query = db.Chats;
        if (includeVideos) query = query.Include(c => c.Videos);
        return await query.FirstOrDefaultAsync(c => c.Id == chatId && c.UserId == user.Id, ct)
               ?? throw new NotFoundException("Chat", chatId);
    }

    /// <summary>Videos queued or produced today (UTC), excluding failed jobs.</summary>
    public async Task<int> CountVideosTodayAsync(Guid userId, CancellationToken ct)
    {
        var since = DateTime.UtcNow.Date;
        return await db.GenerationJobs.CountAsync(
            j => j.Chat!.UserId == userId && j.CreatedAt >= since && j.Stage != GenerationStage.Failed, ct);
    }
}
