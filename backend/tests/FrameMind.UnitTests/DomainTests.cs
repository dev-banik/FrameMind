using FrameMind.Domain.Common;
using FrameMind.Domain.Entities;
using FrameMind.Domain.Enums;
using FrameMind.Domain.ValueObjects;

namespace FrameMind.UnitTests;

public class DomainTests
{
    internal static Script SampleScript(int scenes = 3) => new()
    {
        Title = "The Kite",
        Summary = "A girl and her grandfather build a kite.",
        Scenes = Enumerable.Range(1, scenes).Select(i => new Scene
        {
            Number = i * 10, // deliberately out of sequence
            Visual = $"Visual {i}",
            Narration = $"Narration {i}",
            Dialogues = [new Dialogue { Character = "Mira", Line = $"Line {i}" }],
            DurationSeconds = 5,
        }).ToList(),
    };

    internal static Chat ConfiguredChat()
    {
        var chat = new Chat(Guid.NewGuid(), null, "https://youtu.be/x", null, new VideoAnalysis { Category = "Family Animation" });
        chat.Configure(Language.English, 15, VideoStyle.Animation, VoiceType.Narrator, null);
        chat.SetScript(SampleScript());
        return chat;
    }

    [Fact]
    public void SetScript_renumbers_scenes_and_takes_title()
    {
        var chat = ConfiguredChat();

        Assert.Equal([1, 2, 3], chat.Script!.Scenes.Select(s => s.Number));
        Assert.Equal("The Kite", chat.Title);
        Assert.Equal(ChatStatus.ScriptReady, chat.Status);
        Assert.Equal(15, chat.Script.TotalDurationSeconds);
    }

    [Fact]
    public void ReplaceScene_keeps_number_and_rejects_unknown_scene()
    {
        var script = SampleScript().Renumbered();
        var updated = script.ReplaceScene(2, new Scene { Number = 99, Visual = "New", DurationSeconds = 5 });

        Assert.Equal("New", updated.Scenes[1].Visual);
        Assert.Equal(2, updated.Scenes[1].Number);
        Assert.Throws<DomainException>(() => script.ReplaceScene(7, new Scene()));
    }

    [Fact]
    public void Scene_spoken_text_joins_narration_and_dialogue()
    {
        var scene = SampleScript(1).Scenes[0];
        Assert.Equal("Narration 1 Line 1", scene.SpokenText());
    }

    [Fact]
    public void Chat_cannot_be_edited_or_requeued_while_generating()
    {
        var chat = ConfiguredChat();
        chat.QueueGeneration(Resolution.P720);

        Assert.Equal(ChatStatus.Queued, chat.Status);
        Assert.Throws<DomainException>(() => chat.QueueGeneration(Resolution.P720));
        Assert.Throws<DomainException>(() => chat.SetScript(SampleScript()));
    }

    [Fact]
    public void QueueGeneration_requires_a_script()
    {
        var chat = new Chat(Guid.NewGuid(), null, "https://youtu.be/x", null, new VideoAnalysis());
        Assert.Throws<DomainException>(() => chat.QueueGeneration(Resolution.P720));
    }

    [Fact]
    public void Duplicate_copies_script_but_not_videos()
    {
        var chat = ConfiguredChat();
        chat.MarkCompleted(new GeneratedVideo(chat.Id, "k", null, Resolution.P720, 15));

        var copy = chat.Duplicate();

        Assert.NotEqual(chat.Id, copy.Id);
        Assert.Equal(chat.Script, copy.Script);
        Assert.Empty(copy.Videos);
        Assert.Equal(ChatStatus.ScriptReady, copy.Status);
        Assert.EndsWith("(copy)", copy.Title);
    }

    [Fact]
    public void Job_progress_never_moves_backwards()
    {
        var job = new GenerationJob(Guid.NewGuid(), Resolution.P720);
        job.Advance(GenerationStage.GeneratingVideo, 60);
        job.Advance(GenerationStage.GeneratingVideo, 40);

        Assert.Equal(60, job.Progress);
        job.Complete(Guid.NewGuid());
        Assert.Throws<DomainException>(() => job.Advance(GenerationStage.Rendering, 90));
    }

    [Theory]
    [InlineData(Plan.Free, Resolution.P720, true)]
    [InlineData(Plan.Free, Resolution.P1080, false)]
    [InlineData(Plan.Premium, Resolution.P1080, true)]
    public void Plan_policy_resolution(Plan plan, Resolution resolution, bool allowed) =>
        Assert.Equal(allowed, PlanPolicy.Allows(plan, resolution));

    [Fact]
    public void Plan_policy_limits_and_priority()
    {
        Assert.Equal(3, PlanPolicy.DailyVideoLimit(Plan.Free));
        Assert.Null(PlanPolicy.DailyVideoLimit(Plan.Premium));
        Assert.True(PlanPolicy.QueuePriority(Plan.Premium) > PlanPolicy.QueuePriority(Plan.Free));
    }
}
