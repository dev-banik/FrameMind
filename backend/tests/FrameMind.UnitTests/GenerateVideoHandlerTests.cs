using FrameMind.Application.Abstractions;
using FrameMind.Application.Common;
using FrameMind.Application.Features.Videos;
using FrameMind.Domain.Entities;
using FrameMind.Domain.Enums;
using FrameMind.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace FrameMind.UnitTests;

public class GenerateVideoHandlerTests
{
    private sealed class FakeUser : ICurrentUser
    {
        public string FirebaseUid => "uid-1";
        public string? Name => "Test";
        public string? Email => "t@example.com";
        public string? PhotoUrl => null;
    }

    private sealed class FakeQueue : IGenerationQueue
    {
        public List<(GenerationJobMessage Message, byte Priority)> Sent { get; } = [];
        public Task EnqueueAsync(GenerationJobMessage message, byte priority, CancellationToken ct)
        {
            Sent.Add((message, priority));
            return Task.CompletedTask;
        }
    }

    private sealed class FakeStorage : IFileStorage
    {
        public Task UploadAsync(string key, string localPath, string contentType, CancellationToken ct) => Task.CompletedTask;
        public Task DeleteAsync(string key, CancellationToken ct) => Task.CompletedTask;
        public Uri GetSignedUrl(string key, TimeSpan lifetime, string? downloadFileName = null) => new($"https://cdn.test/{key}");
    }

    private static (AppDbContext Db, GenerateVideoHandler Handler, FakeQueue Queue, UserAccessor Users) Create()
    {
        var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var users = new UserAccessor(db, new FakeUser());
        var queue = new FakeQueue();
        return (db, new GenerateVideoHandler(db, users, queue, new DtoMapper(new FakeStorage())), queue, users);
    }

    private static async Task<Chat> AddChatAsync(AppDbContext db, UserAccessor users)
    {
        var user = await users.GetAsync(CancellationToken.None);
        var chat = DomainTests.ConfiguredChat();
        typeof(Chat).GetProperty(nameof(Chat.UserId))!.SetValue(chat, user.Id);
        db.Chats.Add(chat);
        await db.SaveChangesAsync();
        return chat;
    }

    [Fact]
    public async Task Queues_job_and_publishes_message()
    {
        var (db, handler, queue, users) = Create();
        var chat = await AddChatAsync(db, users);

        var job = await handler.Handle(new GenerateVideoCommand(chat.Id, Resolution.P720), CancellationToken.None);

        Assert.Equal(GenerationStage.Queued, job.Stage);
        Assert.Single(queue.Sent);
        Assert.Equal(job.Id, queue.Sent[0].Message.JobId);
        Assert.Equal(ChatStatus.Queued, (await db.Chats.SingleAsync()).Status);
    }

    [Fact]
    public async Task Free_plan_cannot_render_1080p()
    {
        var (db, handler, queue, users) = Create();
        var chat = await AddChatAsync(db, users);

        await Assert.ThrowsAsync<PlanLimitException>(() =>
            handler.Handle(new GenerateVideoCommand(chat.Id, Resolution.P1080), CancellationToken.None));
        Assert.Empty(queue.Sent);
    }

    [Fact]
    public async Task Free_plan_is_limited_to_three_videos_per_day()
    {
        var (db, handler, _, users) = Create();
        for (var i = 0; i < PlanPolicy.FreeDailyVideoLimit; i++)
        {
            var c = await AddChatAsync(db, users);
            await handler.Handle(new GenerateVideoCommand(c.Id, Resolution.P720), CancellationToken.None);
        }

        var extra = await AddChatAsync(db, users);
        await Assert.ThrowsAsync<QuotaExceededException>(() =>
            handler.Handle(new GenerateVideoCommand(extra.Id, Resolution.P720), CancellationToken.None));
    }

    [Fact]
    public async Task Cannot_generate_for_another_users_chat()
    {
        var (db, handler, _, _) = Create();
        var foreign = DomainTests.ConfiguredChat(); // random UserId
        db.Chats.Add(foreign);
        await db.SaveChangesAsync();

        await Assert.ThrowsAsync<NotFoundException>(() =>
            handler.Handle(new GenerateVideoCommand(foreign.Id, Resolution.P720), CancellationToken.None));
    }
}
