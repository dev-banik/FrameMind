using FluentValidation;
using FrameMind.Application.Common;
using FrameMind.Application.Features.Chats;
using MediatR;
using Microsoft.Extensions.DependencyInjection;

namespace FrameMind.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        var assembly = typeof(DependencyInjection).Assembly;
        services.AddMediatR(cfg =>
        {
            cfg.RegisterServicesFromAssembly(assembly);
            cfg.AddOpenBehavior(typeof(ValidationBehavior<,>));
        });
        services.AddValidatorsFromAssembly(assembly, includeInternalTypes: true);
        services.AddScoped<UserAccessor>();
        services.AddScoped<DtoMapper>();
        services.AddScoped<ChatReader>();
        return services;
    }
}
