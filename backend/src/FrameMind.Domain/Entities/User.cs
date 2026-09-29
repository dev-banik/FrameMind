using FrameMind.Domain.Common;
using FrameMind.Domain.Enums;

namespace FrameMind.Domain.Entities;

public class User : Entity
{
    private User() { }

    public User(string firebaseUid, string name, string email, string? photoUrl)
    {
        FirebaseUid = firebaseUid;
        Name = name;
        Email = email;
        PhotoUrl = photoUrl;
    }

    public string FirebaseUid { get; private set; } = "";
    public string Name { get; private set; } = "";
    public string Email { get; private set; } = "";
    public string? PhotoUrl { get; private set; }
    public Plan Plan { get; private set; } = Plan.Free;

    public ICollection<DeviceToken> DeviceTokens { get; private set; } = new List<DeviceToken>();

    public void UpdateProfile(string name, string email, string? photoUrl)
    {
        Name = name;
        Email = email;
        PhotoUrl = photoUrl;
    }

    public void ChangePlan(Plan plan) => Plan = plan;
}

public class DeviceToken : Entity
{
    private DeviceToken() { }

    public DeviceToken(Guid userId, string token, string platform)
    {
        UserId = userId;
        Token = token;
        Platform = platform;
        LastSeenAt = DateTime.UtcNow;
    }

    public Guid UserId { get; private set; }
    public string Token { get; private set; } = "";
    public string Platform { get; private set; } = "";
    public DateTime LastSeenAt { get; private set; }

    public void Touch(Guid userId, string platform)
    {
        UserId = userId;
        Platform = platform;
        LastSeenAt = DateTime.UtcNow;
    }
}

/// <summary>Plan entitlements from the product spec.</summary>
public static class PlanPolicy
{
    public const int FreeDailyVideoLimit = 3;

    public static int? DailyVideoLimit(Plan plan) => plan == Plan.Premium ? null : FreeDailyVideoLimit;

    public static Resolution MaxResolution(Plan plan) => plan == Plan.Premium ? Resolution.P1080 : Resolution.P720;

    public static bool Allows(Plan plan, Resolution resolution) => resolution <= MaxResolution(plan);

    /// <summary>RabbitMQ message priority (0–9); premium jobs jump the queue.</summary>
    public static byte QueuePriority(Plan plan) => plan == Plan.Premium ? (byte)9 : (byte)1;
}
