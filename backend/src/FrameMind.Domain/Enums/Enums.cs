namespace FrameMind.Domain.Enums;

public enum Language { English, Bangla, Hindi }

public enum VideoStyle { Animation, Realistic, Cartoon, Cinematic, Anime }

public enum VoiceType { Male, Female, Child, Narrator }

public enum Resolution { P720, P1080 }

public enum Plan { Free, Premium }

public enum SourcePlatform { YouTube, Facebook, Instagram, TikTok, Other }

public enum ChatStatus { Analyzed, ScriptReady, Queued, Generating, Completed, Failed }

public enum GenerationStage
{
    Queued,
    Analyzing,
    GeneratingScript,
    GeneratingVoice,
    GeneratingVideo,
    Rendering,
    Complete,
    Failed,
}

public static class ResolutionExtensions
{
    public static (int Width, int Height) Dimensions(this Resolution resolution) => resolution switch
    {
        Resolution.P1080 => (1920, 1080),
        _ => (1280, 720),
    };

    public static string Label(this Resolution resolution) => resolution == Resolution.P1080 ? "1080p" : "720p";
}
