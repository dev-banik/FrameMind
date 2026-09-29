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
        services.Configure<LlmOptions>(config.GetSection(LlmOptions.Section));
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

        // AI: free local Ollama by default, Claude when configured.
        var llm = config.GetSection(LlmOptions.Section).Get<LlmOptions>() ?? new LlmOptions();
        if (llm.Provider == LlmProvider.Claude)
        {
            services.AddSingleton(sp =>
            {
                var key = sp.GetRequiredService<IOptions<AnthropicOptions>>().Value.ApiKey;
                return string.IsNullOrWhiteSpace(key) ? new AnthropicClient() : new AnthropicClient { ApiKey = key };
            });
            services.AddSingleton<ILlmJsonClient, ClaudeJsonClient>();
        }
        else
        {
            services.AddHttpClient("ollama", c => c.Timeout = TimeSpan.FromMinutes(llm.Ollama.TimeoutMinutes));
            services.AddSingleton<ILlmJsonClient, OllamaJsonClient>();
        }
        services.AddScoped<LlmVideoAnalyzer>();
        services.AddScoped<IVideoAnalyzer, CachedVideoAnalyzer>();
        services.AddScoped<IScriptGenerator, LlmScriptGenerator>();

        // Media pipeline
        services.AddHttpClient("media", c => c.Timeout = TimeSpan.FromSeconds(30));
        services.AddHttpClient("elevenlabs", c => c.Timeout = TimeSpan.FromMinutes(2));
        services.AddHttpClient("veo", c => c.Timeout = TimeSpan.FromMinutes(5));
        services.AddSingleton<ProcessRunner>();
        services.AddSingleton<FfmpegTools>();
        services.AddScoped<SourceVideoProbe>();
        services.AddScoped<IVideoAssembler, FfmpegVideoAssembler>();

        services.AddScoped<EspeakVoiceGenerator>();
        var voice = config.GetSection(VoiceOptions.Section).Get<VoiceOptions>() ?? new VoiceOptions();
        switch (voice.Provider)
        {
            case VoiceProvider.ElevenLabs: services.AddScoped<IVoiceGenerator, ElevenLabsVoiceGenerator>(); break;
            case VoiceProvider.Espeak: services.AddScoped<IVoiceGenerator>(sp => sp.GetRequiredService<EspeakVoiceGenerator>()); break;
            case VoiceProvider.Placeholder: services.AddScoped<IVoiceGenerator, PlaceholderVoiceGenerator>(); break;
            default: services.AddScoped<IVoiceGenerator, EdgeTtsVoiceGenerator>(); break;
        }

        services.AddHttpClient("images", c => c.Timeout = TimeSpan.FromMinutes(3));
        services.AddScoped<PlaceholderSceneVideoGenerator>();
        var video = config.GetSection(VideoGenerationOptions.Section).Get<VideoGenerationOptions>() ?? new VideoGenerationOptions();
        switch (video.Provider)
        {
            case VideoProvider.Veo: services.AddScoped<ISceneVideoGenerator, VeoSceneVideoGenerator>(); break;
            case VideoProvider.Placeholder: services.AddScoped<ISceneVideoGenerator>(sp => sp.GetRequiredService<PlaceholderSceneVideoGenerator>()); break;
            default: services.AddScoped<ISceneVideoGenerator, StoryboardSceneVideoGenerator>(); break;
        }

        services.AddSingleton<IPushNotifier, FcmPushNotifier>();
        return services;
    }
}
