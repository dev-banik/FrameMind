using FirebaseAdmin;
using FirebaseAdmin.Messaging;
using FrameMind.Application.Abstractions;
using Google.Apis.Auth.OAuth2;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FrameMind.Infrastructure.Notifications;

public sealed class FcmPushNotifier(IOptions<FirebaseOptions> options, ILogger<FcmPushNotifier> logger) : IPushNotifier
{
    private static readonly object InitLock = new();

    public async Task SendAsync(IReadOnlyCollection<string> deviceTokens, PushMessage message, CancellationToken ct)
    {
        if (!options.Value.PushEnabled || deviceTokens.Count == 0) return;

        var messaging = FirebaseMessaging.GetMessaging(GetApp());
        // FCM accepts at most 500 tokens per multicast.
        foreach (var batch in deviceTokens.Chunk(500))
        {
            var response = await messaging.SendEachForMulticastAsync(new MulticastMessage
            {
                Tokens = batch,
                Notification = new Notification { Title = message.Title, Body = message.Body },
                Data = message.Data,
                Android = new AndroidConfig { Priority = Priority.High },
                Apns = new ApnsConfig { Aps = new Aps { Sound = "default" } },
            }, ct);

            if (response.FailureCount > 0)
                logger.LogInformation("FCM: {Failed}/{Total} deliveries failed", response.FailureCount, batch.Length);
        }
    }

    private FirebaseApp GetApp()
    {
        lock (InitLock)
        {
            if (FirebaseApp.DefaultInstance is { } app) return app;
            var credential = string.IsNullOrWhiteSpace(options.Value.CredentialsPath)
                ? GoogleCredential.GetApplicationDefault()
                : CredentialFactory.FromFile<ServiceAccountCredential>(options.Value.CredentialsPath).ToGoogleCredential();
            return FirebaseApp.Create(new AppOptions { Credential = credential, ProjectId = options.Value.ProjectId });
        }
    }
}
