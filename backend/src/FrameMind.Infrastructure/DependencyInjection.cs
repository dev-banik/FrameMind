using Anthropic;
using FrameMind.Application.Abstractions;
using FrameMind.Infrastructure.AI;
using FrameMind.Infrastructure.Media;
using FrameMind.Infrastructure.Messaging;
using FrameMind.Infrastructure.Notifications;
using FrameMind.Infrastructure.Persistence;
using FrameMind.Infrastructure.Storage;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace FrameMind.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration config)
    {
        services.Configure<AnthropicOptions>(config.GetSection(AnthropicOptions.Section));
        services.Configure<MediaOptions>(config.GetSection(MediaOptions.Section));
        services.Configure<StorageOptions>(config.GetSection(StorageOptions.Section));
        services.Configure<QueueOptions>(config.GetSection(QueueOptions.Section));
        services.Configure<VideoGenerationOptions>(config.GetSection(VideoGenerationOptions.Section));
        services.Configure<VoiceOptions>(config.GetSection(VoiceOptions.Section));
        services.Configure<FirebaseOptions>(config.GetSection(FirebaseOptions.Section));

        // Persistence & cache
        services.AddDbContext<AppDbContext>(o => o.UseNpgsql(
            config.GetConnectionString("Postgres"),
            npgsql => npgsql.EnableRetryOnFailure(3)));
        services.AddScoped<IAppDbContext>(sp => sp.GetRequiredService<AppDbContext>());
        services.AddStackExchangeRedisCache(o =>
        {
            o.Configuration = config.GetConnectionString("Redis");
            o.InstanceName = "framemind:";
        });

        // Messaging & storage
        services.AddSingleton<RabbitMqConnection>();
        services.AddSingleton<IGenerationQueue, RabbitMqGenerationQueue>();
        services.AddSingleton<S3FileStorage>();
        services.AddSingleton<IFileStorage>(sp => sp.GetRequiredService<S3FileStorage>());

        // AI
        services.AddSingleton(sp =>
        {
            var key = sp.GetRequiredService<IOptions<AnthropicOptions>>().Value.ApiKey;
            return string.IsNullOrWhiteSpace(key) ? new AnthropicClient() : new AnthropicClient { ApiKey = key };
        });
        services.AddSingleton<ClaudeJsonClient>();
        services.AddScoped<ClaudeVideoAnalyzer>();
        services.AddScoped<IVideoAnalyzer, CachedVideoAnalyzer>();
        services.AddScoped<IScriptGenerator, ClaudeScriptGenerator>();

        // Media pipeline
        services.AddHttpClient("media", c => c.Timeout = TimeSpan.FromSeconds(30));
        services.AddHttpClient("elevenlabs", c => c.Timeout = TimeSpan.FromMinutes(2));
        services.AddHttpClient("veo", c => c.Timeout = TimeSpan.FromMinutes(5));
        services.AddSingleton<ProcessRunner>();
        services.AddSingleton<FfmpegTools>();
        services.AddScoped<SourceVideoProbe>();
        services.AddScoped<IVideoAssembler, FfmpegVideoAssembler>();

        var voice = config.GetSection(VoiceOptions.Section).Get<VoiceOptions>() ?? new VoiceOptions();
        if (voice.Provider == VoiceProvider.ElevenLabs) services.AddScoped<IVoiceGenerator, ElevenLabsVoiceGenerator>();
        else services.AddScoped<IVoiceGenerator, PlaceholderVoiceGenerator>();

        var video = config.GetSection(VideoGenerationOptions.Section).Get<VideoGenerationOptions>() ?? new VideoGenerationOptions();
        if (video.Provider == VideoProvider.Veo) services.AddScoped<ISceneVideoGenerator, VeoSceneVideoGenerator>();
        else services.AddScoped<ISceneVideoGenerator, PlaceholderSceneVideoGenerator>();

        services.AddSingleton<IPushNotifier, FcmPushNotifier>();
        return services;
    }
}
