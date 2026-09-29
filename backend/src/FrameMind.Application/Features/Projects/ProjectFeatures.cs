using FluentValidation;
using FrameMind.Application.Abstractions;
using FrameMind.Application.Common;
using FrameMind.Domain.Entities;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace FrameMind.Application.Features.Projects;

public sealed record ListProjectsQuery : IRequest<IReadOnlyList<ProjectDto>>;

public sealed class ListProjectsHandler(IAppDbContext db, UserAccessor users)
    : IRequestHandler<ListProjectsQuery, IReadOnlyList<ProjectDto>>
{
    public async Task<IReadOnlyList<ProjectDto>> Handle(ListProjectsQuery request, CancellationToken ct)
    {
        var user = await users.GetAsync(ct);
        return await db.Projects.AsNoTracking()
            .Where(p => p.UserId == user.Id)
            .OrderByDescending(p => p.CreatedAt)
            .Select(p => new ProjectDto(p.Id, p.Name, p.Chats.Count, p.CreatedAt))
            .ToListAsync(ct);
    }
}

public sealed record GetProjectQuery(Guid Id) : IRequest<ProjectDetailDto>;

public sealed class GetProjectHandler(IAppDbContext db, UserAccessor users, DtoMapper mapper)
    : IRequestHandler<GetProjectQuery, ProjectDetailDto>
{
    public async Task<ProjectDetailDto> Handle(GetProjectQuery request, CancellationToken ct)
    {
        var user = await users.GetAsync(ct);
        var project = await db.Projects.AsNoTracking()
            .Include(p => p.Chats).ThenInclude(c => c.Videos)
            .FirstOrDefaultAsync(p => p.Id == request.Id && p.UserId == user.Id, ct)
            ?? throw new NotFoundException("Project", request.Id);

        var chats = project.Chats
            .OrderByDescending(c => c.CreatedAt)
            .Select(c => mapper.Summary(c, c.Videos.MaxBy(v => v.CreatedAt)))
            .ToList();
        return new ProjectDetailDto(project.Id, project.Name, project.CreatedAt, chats);
    }
}

public sealed record CreateProjectCommand(string Name) : IRequest<ProjectDto>;

public sealed record RenameProjectCommand(Guid Id, string Name) : IRequest<ProjectDto>;

public sealed class ProjectNameValidator : AbstractValidator<CreateProjectCommand>
{
    public ProjectNameValidator() => RuleFor(x => x.Name).NotEmpty().MaximumLength(100);
}

public sealed class RenameProjectValidator : AbstractValidator<RenameProjectCommand>
{
    public RenameProjectValidator() => RuleFor(x => x.Name).NotEmpty().MaximumLength(100);
}

public sealed class CreateProjectHandler(IAppDbContext db, UserAccessor users)
    : IRequestHandler<CreateProjectCommand, ProjectDto>
{
    public async Task<ProjectDto> Handle(CreateProjectCommand request, CancellationToken ct)
    {
        var user = await users.GetAsync(ct);
        var project = new Project(user.Id, request.Name);
        db.Projects.Add(project);
        await db.SaveChangesAsync(ct);
        return new ProjectDto(project.Id, project.Name, 0, project.CreatedAt);
    }
}

public sealed class RenameProjectHandler(IAppDbContext db, UserAccessor users)
    : IRequestHandler<RenameProjectCommand, ProjectDto>
{
    public async Task<ProjectDto> Handle(RenameProjectCommand request, CancellationToken ct)
    {
        var user = await users.GetAsync(ct);
        var project = await db.Projects.FirstOrDefaultAsync(p => p.Id == request.Id && p.UserId == user.Id, ct)
                      ?? throw new NotFoundException("Project", request.Id);
        project.Rename(request.Name);
        await db.SaveChangesAsync(ct);
        var count = await db.Chats.CountAsync(c => c.ProjectId == project.Id, ct);
        return new ProjectDto(project.Id, project.Name, count, project.CreatedAt);
    }
}

public sealed record DeleteProjectCommand(Guid Id) : IRequest;

public sealed class DeleteProjectHandler(IAppDbContext db, UserAccessor users) : IRequestHandler<DeleteProjectCommand>
{
    public async Task Handle(DeleteProjectCommand request, CancellationToken ct)
    {
        var user = await users.GetAsync(ct);
        var project = await db.Projects.Include(p => p.Chats)
                          .FirstOrDefaultAsync(p => p.Id == request.Id && p.UserId == user.Id, ct)
                      ?? throw new NotFoundException("Project", request.Id);

        // Chats survive project deletion; they move back to "no project".
        foreach (var chat in project.Chats) chat.MoveToProject(null);
        db.Projects.Remove(project);
        await db.SaveChangesAsync(ct);
    }
}
