using System.Security.Claims;
using System.Text.Encodings.Web;
using FrameMind.Application.Abstractions;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Options;

namespace FrameMind.Api.Auth;

public static class AuthenticationSetup
{
    public const string DevScheme = "Dev";

    /// <summary>
    /// Validates Firebase ID tokens (RS256, issuer/audience = Firebase project).
    /// In Development, <c>Auth:DevBypass=true</c> additionally accepts an
    /// <c>X-Dev-User</c> header so the API can be exercised without Firebase.
    /// </summary>
    public static IServiceCollection AddFirebaseAuthentication(
        this IServiceCollection services, IConfiguration config, IWebHostEnvironment env)
    {
        var projectId = config["Firebase:ProjectId"];
        var devBypass = env.IsDevelopment() && config.GetValue<bool>("Auth:DevBypass");

        var auth = services.AddAuthentication(o =>
        {
            o.DefaultScheme = devBypass ? "Smart" : JwtBearerDefaults.AuthenticationScheme;
            o.DefaultChallengeScheme = devBypass ? "Smart" : JwtBearerDefaults.AuthenticationScheme;
        });

        auth.AddJwtBearer(o =>
        {
            o.Authority = $"https://securetoken.google.com/{projectId}";
            o.MapInboundClaims = false;
            o.TokenValidationParameters = new()
            {
                ValidateIssuer = true,
                ValidIssuer = $"https://securetoken.google.com/{projectId}",
                ValidateAudience = true,
                ValidAudience = projectId,
                ValidateLifetime = true,
                NameClaimType = "name",
            };
        });

        if (devBypass)
        {
            auth.AddScheme<AuthenticationSchemeOptions, DevAuthHandler>(DevScheme, _ => { });
            auth.AddPolicyScheme("Smart", "Firebase or dev header", o =>
                o.ForwardDefaultSelector = ctx => ctx.Request.Headers.ContainsKey(DevAuthHandler.Header)
                    ? DevScheme : JwtBearerDefaults.AuthenticationScheme);
        }

        services.AddAuthorization();
        services.AddHttpContextAccessor();
        services.AddScoped<ICurrentUser, HttpCurrentUser>();
        return services;
    }
}

public sealed class HttpCurrentUser(IHttpContextAccessor accessor) : ICurrentUser
{
    private ClaimsPrincipal Principal =>
        accessor.HttpContext?.User ?? throw new InvalidOperationException("No HTTP context.");

    public string FirebaseUid =>
        Principal.FindFirstValue("user_id") ?? Principal.FindFirstValue("sub")
        ?? throw new UnauthorizedAccessException("Token has no subject.");

    public string? Name => Principal.FindFirstValue("name");
    public string? Email => Principal.FindFirstValue("email");
    public string? PhotoUrl => Principal.FindFirstValue("picture");
}

/// <summary>Development-only: authenticates as the user id in the X-Dev-User header.</summary>
public sealed class DevAuthHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string Header = "X-Dev-User";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var uid = Request.Headers[Header].ToString();
        if (string.IsNullOrWhiteSpace(uid)) return Task.FromResult(AuthenticateResult.NoResult());

        var identity = new ClaimsIdentity(
        [
            new Claim("sub", uid),
            new Claim("name", $"Dev {uid}"),
            new Claim("email", $"{uid}@dev.local"),
        ], Scheme.Name);
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), Scheme.Name)));
    }
}
