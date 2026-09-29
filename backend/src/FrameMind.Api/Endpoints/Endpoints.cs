using FrameMind.Application.Features.Analysis;
using FrameMind.Application.Features.Chats;
using FrameMind.Application.Features.Projects;
using FrameMind.Application.Features.Scripts;
using FrameMind.Application.Features.Users;
using FrameMind.Application.Features.Videos;
using FrameMind.Domain.Enums;
using FrameMind.Domain.ValueObjects;
using MediatR;

namespace FrameMind.Api.Endpoints;

public static class Endpoints
{
    public const string AiPolicy = "ai";
    public const string DefaultPolicy = "default";

    public static void MapFrameMindApi(this IEndpointRouteBuilder app)
    {
        var api = app.MapGroup("/api").RequireAuthorization().RequireRateLimiting(DefaultPolicy);

        var users = api.MapGroup("/users").WithTags("Users");
        users.MapGet("/me", (ISender s, CancellationToken ct) => s.Send(new GetMeQuery(), ct));
        users.MapPost("/me/device-token", async (RegisterDeviceTokenCommand cmd, ISender s, CancellationToken ct) =>
        {
            await s.Send(cmd, ct);
            return Results.NoContent();
        });

        var projects = api.MapGroup("/project").WithTags("Projects");
        projects.MapGet("/", (ISender s, CancellationToken ct) => s.Send(new ListProjectsQuery(), ct));
        projects.MapGet("/{id:guid}", (Guid id, ISender s, CancellationToken ct) => s.Send(new GetProjectQuery(id), ct));
        projects.MapPost("/", async (CreateProjectCommand cmd, ISender s, CancellationToken ct) =>
        {
            var project = await s.Send(cmd, ct);
            return Results.Created($"/api/project/{project.Id}", project);
        });
        projects.MapPut("/{id:guid}", (Guid id, NameBody body, ISender s, CancellationToken ct) =>
            s.Send(new RenameProjectCommand(id, body.Name), ct));
        projects.MapDelete("/{id:guid}", async (Guid id, ISender s, CancellationToken ct) =>
        {
            await s.Send(new DeleteProjectCommand(id), ct);
            return Results.NoContent();
        });

        var video = api.MapGroup("/video").WithTags("Video");
        video.MapPost("/analyze", (AnalyzeVideoCommand cmd, ISender s, CancellationToken ct) => s.Send(cmd, ct))
            .RequireRateLimiting(AiPolicy);
        video.MapPost("/generate", async (GenerateVideoCommand cmd, ISender s, CancellationToken ct) =>
            Results.Accepted(value: await s.Send(cmd, ct)));
        video.MapGet("/jobs/{jobId:guid}", (Guid jobId, ISender s, CancellationToken ct) => s.Send(new GetJobQuery(jobId), ct));
        video.MapGet("/{videoId:guid}/download", (Guid videoId, ISender s, CancellationToken ct) =>
            s.Send(new GetDownloadLinkQuery(videoId), ct));

        var script = api.MapGroup("/script").WithTags("Script");
        script.MapPost("/generate", (GenerateScriptCommand cmd, ISender s, CancellationToken ct) => s.Send(cmd, ct))
            .RequireRateLimiting(AiPolicy);
        script.MapPost("/regenerate", (RegenerateScriptCommand cmd, ISender s, CancellationToken ct) => s.Send(cmd, ct))
            .RequireRateLimiting(AiPolicy);
        script.MapPut("/{chatId:guid}", (Guid chatId, ScriptBody body, ISender s, CancellationToken ct) =>
            s.Send(new SaveScriptCommand(chatId, body.Script), ct));

        api.MapGet("/history", (
                string? search, Guid? projectId, Language? language, ChatStatus? status,
                int? page, int? pageSize, ISender s, CancellationToken ct) =>
            s.Send(new GetHistoryQuery(search, projectId, language, status, page ?? 1, pageSize ?? 20), ct))
            .WithTags("Chats");

        var chat = api.MapGroup("/chat").WithTags("Chats");
        chat.MapGet("/{id:guid}", (Guid id, ISender s, CancellationToken ct) => s.Send(new GetChatQuery(id), ct));
        chat.MapPut("/{id:guid}/project", async (Guid id, ProjectBody body, ISender s, CancellationToken ct) =>
        {
            await s.Send(new MoveChatCommand(id, body.ProjectId), ct);
            return Results.NoContent();
        });
        chat.MapPost("/{id:guid}/duplicate", async (Guid id, ISender s, CancellationToken ct) =>
        {
            var copy = await s.Send(new DuplicateChatCommand(id), ct);
            return Results.Created($"/api/chat/{copy.Id}", copy);
        });
        chat.MapDelete("/{id:guid}", async (Guid id, ISender s, CancellationToken ct) =>
        {
            await s.Send(new DeleteChatCommand(id), ct);
            return Results.NoContent();
        });
    }

    public sealed record NameBody(string Name);
    public sealed record ScriptBody(Script Script);
    public sealed record ProjectBody(Guid? ProjectId);
}
