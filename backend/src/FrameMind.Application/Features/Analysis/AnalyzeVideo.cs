using FluentValidation;
using FrameMind.Application.Abstractions;
using FrameMind.Application.Common;
using FrameMind.Domain.Entities;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace FrameMind.Application.Features.Analysis;

public sealed record AnalyzeVideoCommand(string VideoUrl, Guid? ProjectId, string? UserPrompt) : IRequest<AnalyzeVideoResult>;

public sealed class AnalyzeVideoValidator : AbstractValidator<AnalyzeVideoCommand>
{
    public AnalyzeVideoValidator()
    {
        RuleFor(x => x.VideoUrl)
            .Must(url => VideoUrl.TryParse(url, out _))
            .WithMessage("Enter a valid public video URL (http or https).");
        RuleFor(x => x.UserPrompt).MaximumLength(1000);
    }
}

public sealed class AnalyzeVideoHandler(IAppDbContext db, UserAccessor users, IVideoAnalyzer analyzer)
    : IRequestHandler<AnalyzeVideoCommand, AnalyzeVideoResult>
{
    public async Task<AnalyzeVideoResult> Handle(AnalyzeVideoCommand request, CancellationToken ct)
    {
        var user = await users.GetAsync(ct);
        if (request.ProjectId is { } projectId &&
            !await db.Projects.AnyAsync(p => p.Id == projectId && p.UserId == user.Id, ct))
            throw new NotFoundException("Project", projectId);

        VideoUrl.TryParse(request.VideoUrl, out var uri);
        var analysis = await analyzer.AnalyzeAsync(uri, VideoUrl.DetectPlatform(uri), ct);

        var chat = new Chat(user.Id, request.ProjectId, uri.ToString(), request.UserPrompt?.Trim(), analysis);
        db.Chats.Add(chat);
        await db.SaveChangesAsync(ct);

        return new AnalyzeVideoResult(chat.Id, analysis);
    }
}
