using System.Text.Json;
using FrameMind.Application.Abstractions;
using FrameMind.Application.Features.Videos;
using FrameMind.Infrastructure.Messaging;
using MediatR;
using RabbitMQ.Client;
using RabbitMQ.Client.Events;

namespace FrameMind.Worker;

/// <summary>
/// Consumes video generation jobs. Messages are acked only after the pipeline has
/// recorded a terminal state, so a crashed worker's job is redelivered.
/// </summary>
public sealed class GenerationConsumer(
    RabbitMqConnection connection, IServiceScopeFactory scopes, ILogger<GenerationConsumer> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await ConsumeAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Queue consumer failed; reconnecting in 5s");
                await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
            }
        }
    }

    private async Task ConsumeAsync(CancellationToken stoppingToken)
    {
        var conn = await connection.GetAsync(stoppingToken);
        await using var channel = await conn.CreateChannelAsync(cancellationToken: stoppingToken);
        await connection.DeclareQueueAsync(channel, stoppingToken);
        await channel.BasicQosAsync(0, connection.Options.Prefetch, false, stoppingToken);

        var consumer = new AsyncEventingBasicConsumer(channel);
        consumer.ReceivedAsync += async (_, delivery) =>
        {
            GenerationJobMessage? message = null;
            try
            {
                message = JsonSerializer.Deserialize<GenerationJobMessage>(delivery.Body.Span);
            }
            catch (JsonException ex)
            {
                logger.LogError(ex, "Dropping malformed message {DeliveryTag}", delivery.DeliveryTag);
            }

            if (message is null)
            {
                await channel.BasicAckAsync(delivery.DeliveryTag, false, CancellationToken.None);
                return;
            }

            try
            {
                using var scope = scopes.CreateScope();
                logger.LogInformation("Processing job {JobId} for chat {ChatId}", message.JobId, message.ChatId);
                await scope.ServiceProvider.GetRequiredService<ISender>()
                    .Send(new ProcessGenerationJobCommand(message.JobId), stoppingToken);
                await channel.BasicAckAsync(delivery.DeliveryTag, false, CancellationToken.None);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                await channel.BasicNackAsync(delivery.DeliveryTag, false, requeue: true, CancellationToken.None);
            }
            catch (Exception ex)
            {
                // The pipeline records failures itself; reaching here means infrastructure (e.g. DB) failed.
                logger.LogError(ex, "Job {JobId} could not be processed; requeueing", message.JobId);
                await Task.Delay(TimeSpan.FromSeconds(10), CancellationToken.None);
                await channel.BasicNackAsync(delivery.DeliveryTag, false, requeue: true, CancellationToken.None);
            }
        };

        await channel.BasicConsumeAsync(connection.Options.Name, autoAck: false, consumer, stoppingToken);
        logger.LogInformation("Consuming queue {Queue}", connection.Options.Name);

        // Stay alive until shutdown or the channel drops (then the outer loop reconnects).
        while (!stoppingToken.IsCancellationRequested && channel.IsOpen)
            await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
    }
}
