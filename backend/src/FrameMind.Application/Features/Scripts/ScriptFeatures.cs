using FluentValidation;
using FrameMind.Application.Abstractions;
using FrameMind.Application.Common;
using FrameMind.Application.Features.Chats;
using FrameMind.Domain.Common;
using FrameMind.Domain.Entities;
using FrameMind.Domain.Enums;
using FrameMind.Domain.ValueObjects;
using MediatR;

namespace FrameMind.Application.Features.Scripts;

public static class ScriptLimits
{
    public const int MinDurationSeconds = 15;
    public const int MaxDurationSeconds = 300;
    public const int MaxScenes = 60;
    public const int MaxSceneSeconds = 30;

    internal static ScriptRequest ToRequest(Chat chat) =>
        chat.Language is { } language && chat.Style is { } style && chat.VoiceType is { } voice
            ? new ScriptRequest(chat.Analysis, language, chat.DurationSeconds, style, voice, chat.UserPrompt)
            : throw new DomainException("Configure language, duration, style and voice first.");
}

public sealed record GenerateScriptCommand(
    Guid ChatId, Language Language, int DurationSeconds, VideoStyle Style, VoiceType VoiceType, string? UserPrompt)
    : IRequest<ChatDto>;

public sealed class GenerateScriptValidator : AbstractValidator<GenerateScriptCommand>
{
    public GenerateScriptValidator()
    {
        RuleFor(x => x.Language).IsInEnum();
        RuleFor(x => x.Style).IsInEnum();
        RuleFor(x => x.VoiceType).IsInEnum();
        RuleFor(x => x.DurationSeconds).InclusiveBetween(ScriptLimits.MinDurationSeconds, ScriptLimits.MaxDurationSeconds);
        RuleFor(x => x.UserPrompt).MaximumLength(1000);
    }
}

public sealed class GenerateScriptHandler(IAppDbContext db, UserAccessor users, IScriptGenerator generator, ChatReader reader)
    : IRequestHandler<GenerateScriptCommand, ChatDto>
{
    public async Task<ChatDto> Handle(GenerateScriptCommand request, CancellationToken ct)
    {
        var chat = await users.GetOwnedChatAsync(request.ChatId, ct);
        chat.Configure(request.Language, request.DurationSeconds, request.Style, request.VoiceType, request.UserPrompt);

        var script = await generator.GenerateAsync(ScriptLimits.ToRequest(chat), ct);
        chat.SetScript(script);
        await db.SaveChangesAsync(ct);
        return await reader.ReadAsync(chat.Id, ct);
    }
}

public sealed record RegenerateScriptCommand(Guid ChatId, int? SceneNumber, string? Instructions) : IRequest<ChatDto>;

public sealed class RegenerateScriptValidator : AbstractValidator<RegenerateScriptCommand>
{
    public RegenerateScriptValidator()
    {
        RuleFor(x => x.SceneNumber).GreaterThan(0).When(x => x.SceneNumber.HasValue);
        RuleFor(x => x.Instructions).MaximumLength(1000);
    }
}

public sealed class RegenerateScriptHandler(IAppDbContext db, UserAccessor users, IScriptGenerator generator, ChatReader reader)
    : IRequestHandler<RegenerateScriptCommand, ChatDto>
{
    public async Task<ChatDto> Handle(RegenerateScriptCommand request, CancellationToken ct)
    {
        var chat = await users.GetOwnedChatAsync(request.ChatId, ct);
        var context = ScriptLimits.ToRequest(chat);
        var current = chat.Script ?? throw new DomainException("There is no script to regenerate yet.");

        var updated = request.SceneNumber is { } number
            ? current.ReplaceScene(number, await generator.RegenerateSceneAsync(context, current, number, request.Instructions, ct))
            : await generator.RegenerateScriptAsync(context, current, request.Instructions, ct);

        chat.SetScript(updated);
        await db.SaveChangesAsync(ct);
        return await reader.ReadAsync(chat.Id, ct);
    }
}

public sealed record SaveScriptCommand(Guid ChatId, Script Script) : IRequest<ChatDto>;

public sealed class SaveScriptValidator : AbstractValidator<SaveScriptCommand>
{
    public SaveScriptValidator()
    {
        RuleFor(x => x.Script).NotNull();
        RuleFor(x => x.Script.Title).NotEmpty().MaximumLength(200);
        RuleFor(x => x.Script.Summary).MaximumLength(2000);
        RuleFor(x => x.Script.Characters).Must(c => c.Count <= 20).WithMessage("At most 20 characters.");
        RuleFor(x => x.Script.Scenes).NotEmpty()
            .Must(s => s.Count <= ScriptLimits.MaxScenes).WithMessage($"At most {ScriptLimits.MaxScenes} scenes.");
        RuleFor(x => x.Script.TotalDurationSeconds).LessThanOrEqualTo(ScriptLimits.MaxDurationSeconds)
            .WithMessage($"Total duration must not exceed {ScriptLimits.MaxDurationSeconds} seconds.");
        RuleForEach(x => x.Script.Scenes).ChildRules(scene =>
        {
            scene.RuleFor(s => s.Visual).NotEmpty().MaximumLength(1500);
            scene.RuleFor(s => s.Narration).MaximumLength(1500);
            scene.RuleFor(s => s.CameraDirection).MaximumLength(500);
            scene.RuleFor(s => s.DurationSeconds).InclusiveBetween(1, ScriptLimits.MaxSceneSeconds);
            scene.RuleFor(s => s.Dialogues).Must(d => d.Count <= 20);
            scene.RuleForEach(s => s.Dialogues).ChildRules(d =>
            {
                d.RuleFor(x => x.Character).NotEmpty().MaximumLength(100);
                d.RuleFor(x => x.Line).NotEmpty().MaximumLength(500);
            });
        });
    }
}

public sealed class SaveScriptHandler(IAppDbContext db, UserAccessor users, ChatReader reader)
    : IRequestHandler<SaveScriptCommand, ChatDto>
{
    public async Task<ChatDto> Handle(SaveScriptCommand request, CancellationToken ct)
    {
        var chat = await users.GetOwnedChatAsync(request.ChatId, ct);
        chat.SetScript(request.Script);
        await db.SaveChangesAsync(ct);
        return await reader.ReadAsync(chat.Id, ct);
    }
}
