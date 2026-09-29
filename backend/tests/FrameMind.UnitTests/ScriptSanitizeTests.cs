using FrameMind.Domain.ValueObjects;
using FrameMind.Infrastructure.AI;

namespace FrameMind.UnitTests;

public class ScriptSanitizeTests
{
    private static Script WithDurations(params int[] durations) => new()
    {
        Title = "t",
        Scenes = durations.Select((d, i) => new Scene { Number = i + 5, Visual = $"v{i}", DurationSeconds = d }).ToList(),
    };

    [Fact]
    public void Rescales_scene_durations_to_the_requested_total()
    {
        var result = LlmScriptGenerator.Sanitize(WithDurations(5, 5, 5, 5), 60);

        Assert.Equal(60, result.TotalDurationSeconds);
        Assert.Equal([1, 2, 3, 4], result.Scenes.Select(s => s.Number));
        Assert.All(result.Scenes, s => Assert.InRange(s.DurationSeconds, 2, 30));
    }

    [Fact]
    public void Leaves_close_enough_totals_alone_and_drops_empty_scenes()
    {
        var script = WithDurations(10, 10, 11) with
        {
            Scenes = [.. WithDurations(10, 10, 11).Scenes, new Scene { Visual = "  ", DurationSeconds = 4 }],
        };
        var result = LlmScriptGenerator.Sanitize(script, 30);

        Assert.Equal([10, 10, 11], result.Scenes.Select(s => s.DurationSeconds));
    }

    [Fact]
    public void Rejects_empty_scripts() =>
        Assert.Throws<FrameMind.Application.Common.ExternalServiceException>(() => LlmScriptGenerator.Sanitize(WithDurations(), 30));
}
