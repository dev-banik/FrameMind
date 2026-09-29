namespace FrameMind.Domain.ValueObjects;

public sealed record Script
{
    public string Title { get; init; } = "";
    public string Summary { get; init; } = "";
    public IReadOnlyList<ScriptCharacter> Characters { get; init; } = [];
    public IReadOnlyList<Scene> Scenes { get; init; } = [];

    public int TotalDurationSeconds => Scenes.Sum(s => s.DurationSeconds);

    /// <summary>Returns a copy with scenes numbered 1..n in their current order.</summary>
    public Script Renumbered() =>
        this with { Scenes = Scenes.Select((s, i) => s with { Number = i + 1 }).ToList() };

    public Script ReplaceScene(int number, Scene replacement)
    {
        if (Scenes.All(s => s.Number != number))
            throw new Common.DomainException($"Scene {number} does not exist.");

        return this with
        {
            Scenes = Scenes.Select(s => s.Number == number ? replacement with { Number = number } : s).ToList(),
        };
    }
}

public sealed record ScriptCharacter
{
    public string Name { get; init; } = "";
    public string Description { get; init; } = "";
}

public sealed record Scene
{
    public int Number { get; init; }
    public string Visual { get; init; } = "";
    public string Narration { get; init; } = "";
    public IReadOnlyList<Dialogue> Dialogues { get; init; } = [];
    public string CameraDirection { get; init; } = "";
    public int DurationSeconds { get; init; } = 5;

    /// <summary>All spoken text of the scene, narration first, in reading order.</summary>
    public string SpokenText()
    {
        var parts = new List<string>();
        if (!string.IsNullOrWhiteSpace(Narration)) parts.Add(Narration.Trim());
        parts.AddRange(Dialogues.Where(d => !string.IsNullOrWhiteSpace(d.Line)).Select(d => d.Line.Trim()));
        return string.Join(" ", parts);
    }
}

public sealed record Dialogue
{
    public string Character { get; init; } = "";
    public string Line { get; init; } = "";
}
