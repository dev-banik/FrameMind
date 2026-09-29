namespace FrameMind.Infrastructure.AI;

public abstract record LlmPart;
public sealed record LlmText(string Text) : LlmPart;
public sealed record LlmJpeg(byte[] Bytes) : LlmPart;

public enum LlmEffort { Low, Medium, High }

/// <summary>
/// Provider-neutral "prompt in, schema-shaped JSON out" call used by analysis,
/// script writing and scene prompting. Implemented for Ollama (free, local) and Claude.
/// </summary>
public interface ILlmJsonClient
{
    Task<T> CompleteAsync<T>(string system, IReadOnlyList<LlmPart> parts, string jsonSchema, LlmEffort effort, CancellationToken ct);

    /// <summary>Max keyframes worth sending; small local vision models are slow per image.</summary>
    int MaxImages { get; }
}
