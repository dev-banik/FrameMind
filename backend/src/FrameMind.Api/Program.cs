using System.Security.Claims;
using System.Text.Json.Serialization;
using System.Threading.RateLimiting;
using FrameMind.Api.Auth;
using FrameMind.Api.Endpoints;
using FrameMind.Api.Infrastructure;
using FrameMind.Application;
using FrameMind.Infrastructure;
using FrameMind.Infrastructure.Persistence;
using FrameMind.Infrastructure.Storage;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);
builder.Services.AddFirebaseAuthentication(builder.Configuration, builder.Environment);

builder.Services.ConfigureHttpJsonOptions(o =>
{
    o.SerializerOptions.Converters.Add(new JsonStringEnumConverter());
    o.SerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.Never;
});
builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<ProblemExceptionHandler>();
builder.Services.AddOpenApi();
builder.Services.AddHealthChecks();

builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    static string Partition(HttpContext http) =>
        http.User.FindFirstValue("sub") ?? http.Connection.RemoteIpAddress?.ToString() ?? "anonymous";

    o.AddPolicy(Endpoints.DefaultPolicy, http => RateLimitPartition.GetFixedWindowLimiter(Partition(http),
        _ => new FixedWindowRateLimiterOptions { PermitLimit = 120, Window = TimeSpan.FromMinutes(1) }));
    // Analysis and script calls hit paid LLM APIs.
    o.AddPolicy(Endpoints.AiPolicy, http => RateLimitPartition.GetSlidingWindowLimiter(Partition(http),
        _ => new SlidingWindowRateLimiterOptions { PermitLimit = 10, Window = TimeSpan.FromMinutes(1), SegmentsPerWindow = 6 }));
});

builder.Services.Configure<ForwardedHeadersOptions>(o =>
{
    o.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    o.KnownNetworks.Clear();
    o.KnownProxies.Clear();
});

var app = builder.Build();

if (app.Configuration.GetValue<bool>("Database:MigrateOnStartup"))
{
    using var scope = app.Services.CreateScope();
    await scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.MigrateAsync();
}
await app.Services.GetRequiredService<S3FileStorage>().EnsureBucketAsync(CancellationToken.None);

app.UseForwardedHeaders();
app.UseExceptionHandler();
app.UseStatusCodePages();
if (!app.Environment.IsDevelopment()) app.UseHsts();

app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();

if (app.Environment.IsDevelopment()) app.MapOpenApi();
app.MapHealthChecks("/health");
app.MapFrameMindApi();

app.Run();

public partial class Program;
