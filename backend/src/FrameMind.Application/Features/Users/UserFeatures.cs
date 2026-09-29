using FluentValidation;
using FrameMind.Application.Abstractions;
using FrameMind.Application.Common;
using FrameMind.Domain.Entities;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace FrameMind.Application.Features.Users;

public sealed record GetMeQuery : IRequest<UserProfileDto>;

public sealed class GetMeHandler(UserAccessor users) : IRequestHandler<GetMeQuery, UserProfileDto>
{
    public async Task<UserProfileDto> Handle(GetMeQuery request, CancellationToken ct)
    {
        var user = await users.GetAsync(ct);
        var today = await users.CountVideosTodayAsync(user.Id, ct);
        return new UserProfileDto(user.Id, user.Name, user.Email, user.PhotoUrl, user.Plan, today,
            PlanPolicy.DailyVideoLimit(user.Plan), PlanPolicy.MaxResolution(user.Plan));
    }
}

public sealed record RegisterDeviceTokenCommand(string Token, string Platform) : IRequest;

public sealed class RegisterDeviceTokenValidator : AbstractValidator<RegisterDeviceTokenCommand>
{
    public RegisterDeviceTokenValidator()
    {
        RuleFor(x => x.Token).NotEmpty().MaximumLength(4096);
        RuleFor(x => x.Platform).Must(p => p is "android" or "ios").WithMessage("Platform must be 'android' or 'ios'.");
    }
}

public sealed class RegisterDeviceTokenHandler(IAppDbContext db, UserAccessor users)
    : IRequestHandler<RegisterDeviceTokenCommand>
{
    public async Task Handle(RegisterDeviceTokenCommand request, CancellationToken ct)
    {
        var user = await users.GetAsync(ct);
        // A device token belongs to whoever signed in on that device most recently.
        var existing = await db.DeviceTokens.FirstOrDefaultAsync(t => t.Token == request.Token, ct);
        if (existing is null) db.DeviceTokens.Add(new DeviceToken(user.Id, request.Token, request.Platform));
        else existing.Touch(user.Id, request.Platform);
        await db.SaveChangesAsync(ct);
    }
}
