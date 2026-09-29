using System.Text.Json;
using System.Text.Json.Serialization;
using FrameMind.Application.Abstractions;
using FrameMind.Domain.Entities;
using FrameMind.Domain.ValueObjects;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Design;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FrameMind.Infrastructure.Persistence;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options), IAppDbContext
{
    public DbSet<User> Users => Set<User>();
    public DbSet<DeviceToken> DeviceTokens => Set<DeviceToken>();
    public DbSet<Project> Projects => Set<Project>();
    public DbSet<Chat> Chats => Set<Chat>();
    public DbSet<GenerationJob> GenerationJobs => Set<GenerationJob>();
    public DbSet<GeneratedVideo> GeneratedVideos => Set<GeneratedVideo>();

    internal static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter() },
    };

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<User>(e =>
        {
            e.ToTable("users");
            e.Property(x => x.FirebaseUid).HasMaxLength(128);
            e.HasIndex(x => x.FirebaseUid).IsUnique();
            e.Property(x => x.Name).HasMaxLength(200);
            e.Property(x => x.Email).HasMaxLength(320);
            e.Property(x => x.PhotoUrl).HasMaxLength(2048);
            e.Property(x => x.Plan).HasConversion<string>().HasMaxLength(20);
            e.HasMany(x => x.DeviceTokens).WithOne().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<DeviceToken>(e =>
        {
            e.ToTable("device_tokens");
            e.Property(x => x.Token).HasMaxLength(4096);
            e.HasIndex(x => x.Token).IsUnique();
            e.Property(x => x.Platform).HasMaxLength(20);
        });

        b.Entity<Project>(e =>
        {
            e.ToTable("projects");
            e.Property(x => x.Name).HasMaxLength(100);
            e.HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => new { x.UserId, x.CreatedAt });
        });

        b.Entity<Chat>(e =>
        {
            e.ToTable("chats");
            e.Property(x => x.Title).HasMaxLength(200);
            e.Property(x => x.UserPrompt).HasMaxLength(1000);
            e.Property(x => x.VideoUrl).HasMaxLength(2048);
            e.Property(x => x.ThumbnailUrl).HasMaxLength(2048);
            e.Property(x => x.Language).HasConversion<string>().HasMaxLength(20);
            e.Property(x => x.Style).HasConversion<string>().HasMaxLength(20);
            e.Property(x => x.VoiceType).HasConversion<string>().HasMaxLength(20);
            e.Property(x => x.Status).HasConversion<string>().HasMaxLength(20);
            Json(e.Property(x => x.Analysis));
            Json(e.Property(x => x.Script));
            e.HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Project).WithMany(p => p.Chats).HasForeignKey(x => x.ProjectId).OnDelete(DeleteBehavior.SetNull);
            e.HasMany(x => x.Videos).WithOne().HasForeignKey(v => v.ChatId).OnDelete(DeleteBehavior.Cascade);
            e.HasMany(x => x.Jobs).WithOne(j => j.Chat).HasForeignKey(j => j.ChatId).OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => new { x.UserId, x.CreatedAt });
            e.HasIndex(x => x.ProjectId);
            e.Ignore(x => x.IsGenerating);
        });

        b.Entity<GenerationJob>(e =>
        {
            e.ToTable("generation_jobs");
            e.Property(x => x.Resolution).HasConversion<string>().HasMaxLength(10);
            e.Property(x => x.Stage).HasConversion<string>().HasMaxLength(30);
            e.Property(x => x.Error).HasMaxLength(1000);
            e.HasIndex(x => new { x.ChatId, x.CreatedAt });
            e.HasIndex(x => x.CreatedAt);
            e.Ignore(x => x.IsFinished);
        });

        b.Entity<GeneratedVideo>(e =>
        {
            e.ToTable("generated_videos");
            e.Property(x => x.StorageKey).HasMaxLength(512);
            e.Property(x => x.ThumbnailKey).HasMaxLength(512);
            e.Property(x => x.Resolution).HasConversion<string>().HasMaxLength(10);
            e.HasIndex(x => new { x.ChatId, x.CreatedAt });
        });
    }

    private static void Json<T>(PropertyBuilder<T> property)
    {
        property
            .HasColumnType("jsonb")
            .HasConversion(
                v => JsonSerializer.Serialize(v, JsonOptions),
                v => JsonSerializer.Deserialize<T>(v, JsonOptions)!,
                new ValueComparer<T>(
                    (a, c) => JsonSerializer.Serialize(a, JsonOptions) == JsonSerializer.Serialize(c, JsonOptions),
                    v => JsonSerializer.Serialize(v, JsonOptions).GetHashCode(),
                    v => JsonSerializer.Deserialize<T>(JsonSerializer.Serialize(v, JsonOptions), JsonOptions)!));
    }
}

/// <summary>Used by `dotnet ef` at design time.</summary>
public sealed class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<AppDbContext>
{
    public AppDbContext CreateDbContext(string[] args) =>
        new(new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql("Host=localhost;Database=framemind;Username=framemind;Password=framemind")
            .Options);
}
