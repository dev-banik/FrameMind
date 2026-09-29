using FrameMind.Domain.Enums;

namespace FrameMind.Infrastructure;

public sealed class AnthropicOptions
{
    public const string Section = "Anthropic";
    public string? ApiKey { get; set; }
    public string Model { get; set; } = "claude-opus-5-5";
}

public sealed class MediaOptions
{
    public const string Section = "Media";
    public string YtDlpPath { get; set; } = "yt-dlp";
    public string FfmpegPath { get; set; } = "ffmpeg";
    public string FfprobePath { get; set; } = "ffprobe";
    public int KeyframeCount { get; set; } = 8;
    public int MaxDownloadMegabytes { get; set; } = 200;
    public int MaxSourceDurationSeconds { get; set; } = 1800;
    public string SubtitleFont { get; set; } = "Noto Sans";
    public double TransitionSeconds { get; set; } = 0.5;
}

public sealed class StorageOptions
{
    public const string Section = "Storage";
    public string Bucket { get; set; } = "framemind";
    public string Region { get; set; } = "us-east-1";
    /// <summary>S3-compatible endpoint (Cloudflare R2, MinIO). Empty = AWS S3.</summary>
    public string? ServiceUrl { get; set; }
    /// <summary>Endpoint used when signing URLs for clients, if it differs from <see cref="ServiceUrl"/>.</summary>
    public string? PublicServiceUrl { get; set; }
    public string? AccessKey { get; set; }
    public string? SecretKey { get; set; }
    public bool ForcePathStyle { get; set; }
    /// <summary>Request SSE-S3 (AES-256) encryption at rest. R2 always encrypts and ignores this.</summary>
    public bool ServerSideEncryption { get; set; }
    public bool CreateBucketIfMissing { get; set; }
}

public sealed class QueueOptions
{
    public const string Section = "Queue";
    public string Name { get; set; } = "video-generation";
    public ushort Prefetch { get; set; } = 1;
}

public enum VideoProvider { Placeholder, Veo }

public sealed class VideoGenerationOptions
{
    public const string Section = "VideoGeneration";
    public VideoProvider Provider { get; set; } = VideoProvider.Placeholder;
    public VeoOptions Veo { get; set; } = new();
}

public sealed class VeoOptions
{
    public string? ApiKey { get; set; }
    public string BaseUrl { get; set; } = "https://generativelanguage.googleapis.com/v1beta";
    public string Model { get; set; } = "veo-3.0-generate-001";
    public int ClipSeconds { get; set; } = 8;
    public int PollIntervalSeconds { get; set; } = 10;
    public int TimeoutMinutes { get; set; } = 10;
}

public enum VoiceProvider { Placeholder, ElevenLabs }

public sealed class VoiceOptions
{
    public const string Section = "Voice";
    public VoiceProvider Provider { get; set; } = VoiceProvider.Placeholder;
    public ElevenLabsOptions ElevenLabs { get; set; } = new();
}

public sealed class ElevenLabsOptions
{
    public string? ApiKey { get; set; }
    public string BaseUrl { get; set; } = "https://api.elevenlabs.io/v1";
    public string OutputFormat { get; set; } = "mp3_44100_128";

    /// <summary>Voice id per voice type. Defaults are ElevenLabs premade voices; override with your own.</summary>
    public Dictionary<VoiceType, string> Voices { get; set; } = new()
    {
        [VoiceType.Male] = "pNInz6obpgDQGcFmaJgB",
        [VoiceType.Female] = "21m00Tcm4TlvDq8ikWAM",
        [VoiceType.Child] = "jBpfuIE2acCO8z3wKNLl",
        [VoiceType.Narrator] = "JBFqnCBsd6RMkjVDRZzb",
    };

    /// <summary>TTS model per language; Bangla needs a model with Bengali support.</summary>
    public Dictionary<Language, string> Models { get; set; } = new()
    {
        [Language.English] = "eleven_multilingual_v2",
        [Language.Hindi] = "eleven_multilingual_v2",
        [Language.Bangla] = "eleven_v3",
    };
}

public sealed class FirebaseOptions
{
    public const string Section = "Firebase";
    public string? ProjectId { get; set; }
    /// <summary>Service-account JSON path; falls back to GOOGLE_APPLICATION_CREDENTIALS.</summary>
    public string? CredentialsPath { get; set; }
    public bool PushEnabled { get; set; }
}
