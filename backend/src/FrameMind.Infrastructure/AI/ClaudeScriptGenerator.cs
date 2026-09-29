using System.Text;
using System.Text.Json;
using Anthropic.Models.Beta.Messages;
using FrameMind.Application.Abstractions;
using FrameMind.Domain.Enums;
using FrameMind.Domain.ValueObjects;
using FrameMind.Infrastructure.Persistence;

namespace FrameMind.Infrastructure.AI;

public sealed class ClaudeScriptGenerator(ClaudeJsonClient claude) : IScriptGenerator
{
    private const string System = """
        You are an award-winning short-form video writer and storyboard artist.

        You receive the abstract creative profile of an existing video (genre, theme,
        mood, pacing, story pattern). Write a COMPLETELY ORIGINAL script that a viewer
        would recognize as the same kind of video, but which shares nothing specific
        with the source: invent new characters with new names, a new setting, a new
        plot and new dialogue. Never reference the source video, its creator, real
        people, brands or copyrighted characters.

        Craft rules:
        - Hit the requested total duration: scene durations must sum to it (±2 seconds).
          Typical scenes are 3–8 seconds; never exceed 30 seconds for one scene.
        - Narration + dialogue in a scene must be speakable within that scene's duration
          (about 2.5 words per second in English; fewer for Bangla/Hindi).
        - Write "title", "summary", "narration" and dialogue "line" in the requested
          language, using its native script (Bengali script for Bangla, Devanagari for Hindi).
        - Write "visual", "cameraDirection" and character "description" in English, as
          concrete, filmable descriptions for an AI video model: subject, action,
          setting, lighting. Keep each character's look consistent across scenes.
        - Content must be suitable for all audiences.
        """;

    private const string ScriptSchema = """
        {
          "type": "object",
          "additionalProperties": false,
          "required": ["title", "summary", "characters", "scenes"],
          "properties": {
            "title": { "type": "string" },
            "summary": { "type": "string" },
            "characters": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["name", "description"],
                "properties": {
                  "name": { "type": "string" },
                  "description": { "type": "string", "description": "Age, appearance, clothing, personality (English)" }
                }
              }
            },
            "scenes": { "type": "array", "items": SCENE }
          }
        }
        """;

    private const string SceneSchema = """
        {
          "type": "object",
          "additionalProperties": false,
          "required": ["number", "visual", "narration", "dialogues", "cameraDirection", "durationSeconds"],
          "properties": {
            "number": { "type": "integer" },
            "visual": { "type": "string" },
            "narration": { "type": "string" },
            "dialogues": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["character", "line"],
                "properties": { "character": { "type": "string" }, "line": { "type": "string" } }
              }
            },
            "cameraDirection": { "type": "string" },
            "durationSeconds": { "type": "integer" }
          }
        }
        """;

    private const string PromptsSchema = """
        {
          "type": "object",
          "additionalProperties": false,
          "required": ["scenes"],
          "properties": {
            "scenes": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["number", "prompt"],
                "properties": { "number": { "type": "integer" }, "prompt": { "type": "string" } }
              }
            }
          }
        }
        """;

    private static readonly string FullScriptSchema = ScriptSchema.Replace("SCENE", SceneSchema);

    public async Task<Script> GenerateAsync(ScriptRequest request, CancellationToken ct)
    {
        var prompt = Brief(request) + "\nWrite the script now.";
        var script = await claude.CompleteAsync<Script>(System, [ClaudeJsonClient.Text(prompt)], FullScriptSchema, Effort.Medium, ct);
        return Sanitize(script);
    }

    public async Task<Script> RegenerateScriptAsync(ScriptRequest request, Script previous, string? instructions, CancellationToken ct)
    {
        var prompt = new StringBuilder(Brief(request))
            .AppendLine()
            .AppendLine("The user wants a fresh take. Here is the previous draft; write a clearly different story (new premise and characters) that still fits the brief:")
            .AppendLine(Serialize(previous))
            .AppendLine(Instructions(instructions))
            .ToString();
        var script = await claude.CompleteAsync<Script>(System, [ClaudeJsonClient.Text(prompt)], FullScriptSchema, Effort.Medium, ct);
        return Sanitize(script);
    }

    public async Task<Scene> RegenerateSceneAsync(
        ScriptRequest request, Script script, int sceneNumber, string? instructions, CancellationToken ct)
    {
        var current = script.Scenes.First(s => s.Number == sceneNumber);
        var prompt = new StringBuilder(Brief(request))
            .AppendLine()
            .AppendLine("Here is the current full script:")
            .AppendLine(Serialize(script))
            .AppendLine()
            .AppendLine($"Rewrite ONLY scene {sceneNumber}. Keep it consistent with the surrounding scenes and characters, " +
                        $"keep its duration at {current.DurationSeconds} seconds, and make it noticeably better or different.")
            .AppendLine(Instructions(instructions))
            .ToString();
        var scene = await claude.CompleteAsync<Scene>(System, [ClaudeJsonClient.Text(prompt)], SceneSchema, Effort.Low, ct);
        return scene with { Number = sceneNumber, DurationSeconds = current.DurationSeconds };
    }

    public async Task<IReadOnlyList<ScenePrompt>> BuildScenePromptsAsync(Script script, VideoStyle style, CancellationToken ct)
    {
        const string system = """
            You write prompts for a text-to-video model. For each scene, produce one
            self-contained English prompt (60–120 words) that includes: the visual style,
            the full physical description of every character who appears (repeat it
            verbatim in every scene so they look identical), setting, action, lighting,
            mood and camera movement. No on-screen text, captions, logos or watermarks.
            Do not include dialogue or narration.
            """;
        var prompt = $"""
            Visual style: {StyleDirection(style)}

            Script:
            {Serialize(script)}

            Return one prompt per scene, using the same scene numbers.
            """;

        var result = await claude.CompleteAsync<PromptsResult>(system, [ClaudeJsonClient.Text(prompt)], PromptsSchema, Effort.Low, ct);
        var byNumber = result.Scenes.GroupBy(s => s.Number).ToDictionary(g => g.Key, g => g.First().Prompt);

        // Fall back to a mechanical prompt for any scene the model skipped.
        return script.Scenes.Select(s => new ScenePrompt(
            s.Number,
            byNumber.TryGetValue(s.Number, out var p) && !string.IsNullOrWhiteSpace(p)
                ? p
                : $"{StyleDirection(style)}. {s.Visual} Camera: {s.CameraDirection}.",
            s.DurationSeconds)).ToList();
    }

    private sealed record PromptsResult(List<PromptItem> Scenes);
    private sealed record PromptItem(int Number, string Prompt);

    private static string Brief(ScriptRequest r)
    {
        var a = r.Inspiration;
        var sb = new StringBuilder()
            .AppendLine("Inspiration profile (abstract attributes only):")
            .AppendLine($"- Category: {a.Category}")
            .AppendLine($"- Theme: {a.Theme}")
            .AppendLine($"- Mood: {a.Mood}")
            .AppendLine($"- Pace: {a.Pace}")
            .AppendLine($"- Story pattern: {a.StoryPattern}")
            .AppendLine($"- Character archetypes: {string.Join(", ", a.Characters)}")
            .AppendLine()
            .AppendLine("Requirements:")
            .AppendLine($"- Language: {LanguageName(r.Language)}")
            .AppendLine($"- Total duration: {r.DurationSeconds} seconds")
            .AppendLine($"- Visual style: {StyleDirection(r.Style)}")
            .AppendLine($"- Voice: {VoiceDirection(r.VoiceType)}");
        if (!string.IsNullOrWhiteSpace(r.UserPrompt))
            sb.AppendLine($"- Creator's direction (follow it unless it conflicts with the rules): {r.UserPrompt}");
        return sb.ToString();
    }

    private static string Instructions(string? instructions) =>
        string.IsNullOrWhiteSpace(instructions) ? "" : $"User instructions for this rewrite: {instructions}";

    private static string LanguageName(Language l) => l switch
    {
        Language.Bangla => "Bangla (Bengali script)",
        Language.Hindi => "Hindi (Devanagari script)",
        _ => "English",
    };

    internal static string StyleDirection(VideoStyle s) => s switch
    {
        VideoStyle.Animation => "Pixar-style 3D animation, soft global illumination, expressive characters, highly detailed",
        VideoStyle.Realistic => "Photorealistic live-action footage, natural lighting, shallow depth of field",
        VideoStyle.Cartoon => "Vibrant 2D cartoon, clean bold outlines, flat colors, playful exaggerated motion",
        VideoStyle.Cinematic => "Cinematic film look, anamorphic lens, dramatic lighting, rich color grade, 35mm",
        VideoStyle.Anime => "Japanese anime style, cel shading, detailed painted backgrounds, dynamic framing",
        _ => s.ToString(),
    };

    private static string VoiceDirection(VoiceType v) => v switch
    {
        VoiceType.Male => "adult male voice",
        VoiceType.Female => "adult female voice",
        VoiceType.Child => "child's voice — keep vocabulary simple",
        _ => "warm storyteller narrator",
    };

    private static string Serialize(Script s) => JsonSerializer.Serialize(s, AppDbContext.JsonOptions);

    /// <summary>Clamp model output to the limits the rest of the pipeline assumes.</summary>
    private static Script Sanitize(Script s) => (s with
    {
        Scenes = s.Scenes
            .Where(x => !string.IsNullOrWhiteSpace(x.Visual))
            .Take(60)
            .Select(x => x with { DurationSeconds = Math.Clamp(x.DurationSeconds, 1, 30) })
            .ToList(),
    }).Renumbered();
}
