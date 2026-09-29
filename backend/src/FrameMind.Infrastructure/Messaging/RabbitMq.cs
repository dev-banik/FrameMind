using System.Text.Json;
using FrameMind.Application.Abstractions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;
using RabbitMQ.Client;

namespace FrameMind.Infrastructure.Messaging;

/// <summary>Owns the single long-lived AMQP connection for the process.</summary>
public sealed class RabbitMqConnection(IConfiguration configuration, IOptions<QueueOptions> options) : IAsyncDisposable
{
    private readonly SemaphoreSlim _lock = new(1, 1);
    private IConnection? _connection;

    public QueueOptions Options => options.Value;

    public async Task<IConnection> GetAsync(CancellationToken ct)
    {
        if (_connection is { IsOpen: true }) return _connection;
        await _lock.WaitAsync(ct);
        try
        {
            if (_connection is { IsOpen: true }) return _connection;
            var factory = new ConnectionFactory
            {
                Uri = new Uri(configuration.GetConnectionString("RabbitMq") ?? "amqp://guest:guest@localhost:5672"),
                AutomaticRecoveryEnabled = true,
                ClientProvidedName = "framemind",
            };
            _connection = await factory.CreateConnectionAsync(ct);
            return _connection;
        }
        finally { _lock.Release(); }
    }

    /// <summary>Durable priority queue; premium jobs are published with a higher priority.</summary>
    public Task DeclareQueueAsync(IChannel channel, CancellationToken ct) =>
        channel.QueueDeclareAsync(Options.Name, durable: true, exclusive: false, autoDelete: false,
            arguments: new Dictionary<string, object?> { ["x-max-priority"] = 10 }, cancellationToken: ct);

    public async ValueTask DisposeAsync()
    {
        if (_connection is not null) await _connection.DisposeAsync();
        _lock.Dispose();
    }
}

public sealed class RabbitMqGenerationQueue(RabbitMqConnection connection) : IGenerationQueue, IAsyncDisposable
{
    private readonly SemaphoreSlim _lock = new(1, 1);
    private IChannel? _channel;

    public async Task EnqueueAsync(GenerationJobMessage message, byte priority, CancellationToken ct)
    {
        var body = JsonSerializer.SerializeToUtf8Bytes(message);
        var props = new BasicProperties
        {
            Persistent = true,
            Priority = priority,
            ContentType = "application/json",
            MessageId = message.JobId.ToString(),
        };

        // Channels are not safe for concurrent publishing.
        await _lock.WaitAsync(ct);
        try
        {
            if (_channel is not { IsOpen: true })
            {
                var conn = await connection.GetAsync(ct);
                _channel = await conn.CreateChannelAsync(cancellationToken: ct);
                await connection.DeclareQueueAsync(_channel, ct);
            }
            await _channel.BasicPublishAsync(string.Empty, connection.Options.Name, mandatory: false, props, body, ct);
        }
        finally { _lock.Release(); }
    }

    public async ValueTask DisposeAsync()
    {
        if (_channel is not null) await _channel.DisposeAsync();
        _lock.Dispose();
    }
}
