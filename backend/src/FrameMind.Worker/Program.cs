using FrameMind.Application;
using FrameMind.Application.Abstractions;
using FrameMind.Infrastructure;
using FrameMind.Worker;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);
builder.Services.AddSingleton<ICurrentUser, NoCurrentUser>();
builder.Services.AddHostedService<GenerationConsumer>();
builder.Services.AddHostedService<StaleJobSweeper>();

builder.Build().Run();

/// <summary>The worker acts on behalf of the system, never a signed-in user.</summary>
internal sealed class NoCurrentUser : ICurrentUser
{
    private static InvalidOperationException NoUser() => new("There is no current user in the worker.");
    public string FirebaseUid => throw NoUser();
    public string? Name => throw NoUser();
    public string? Email => throw NoUser();
    public string? PhotoUrl => throw NoUser();
}
