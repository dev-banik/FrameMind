using System.Text.Json;
using Anthropic;
using Anthropic.Exceptions;
using Anthropic.Models.Beta.Messages;
using FrameMind.Application.Common;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FrameMind.Infrastructure.AI;

/// <summary>
/// Thin wrapper over the Anthropic Messages API that returns schema-validated JSON
/// (structured outputs) deserialized to <typeparamref name="T"/>.
/// </summary>
public sealed class ClaudeJsonClient(AnthropicClient client, IOptions<AnthropicOptions> options, ILogger<ClaudeJsonClient> logger)
    : ILlmJsonClient
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public async Task<T> CompleteAsync<T>(
        string system, IReadOnlyList<LlmPart> parts, string jsonSchema, LlmEffort effort, CancellationToken ct)
    {
        var schema = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(jsonSchema)!;

        BetaMessage response;
        try
        {
            response = await client.Beta.Messages.Create(new MessageCreateParams
            {
                Model = options.Value.Model,
                MaxTokens = 16000,
                // Route policy declines to the server-defined fallback model instead of failing the request.
                Betas = ["server-side-fallback-2026-07-01"],
                Fallbacks = new Default(),
                System = system,
                OutputConfig = new BetaOutputConfig
                {
                    Effort = effort switch { LlmEffort.Low => Effort.Low, LlmEffort.High => Effort.High, _ => Effort.Medium },
                    Format = new BetaJsonOutputFormat { Schema = schema },
                },
                Messages = [new BetaMessageParam { Role = Role.User, Content = parts.Select(ToBlock).ToList() }],
            }, ct);
        }
        catch (AnthropicRateLimitException ex)
        {
            throw new ExternalServiceException("The AI service is busy. Please try again in a minute.", ex);
        }
        catch (AnthropicApiException ex)
        {
            logger.LogError(ex, "Claude request failed");
            throw new ExternalServiceException("The AI service returned an error. Please try again.", ex);
        }

        if (response.StopReason == "refusal")
            throw new ExternalServiceException("This request can't be processed. Try a different video or prompt.");
        if (response.StopReason == "max_tokens")
            throw new ExternalServiceException("The AI response was too long. Try a shorter duration.");

        var text = string.Concat(response.Content.Select(b => b.Value).OfType<BetaTextBlock>().Select(t => t.Text));
        try
        {
            return JsonSerializer.Deserialize<T>(text, Json)
                   ?? throw new JsonException("Empty response.");
        }
        catch (JsonException ex)
        {
            logger.LogError(ex, "Claude returned JSON that did not match {Type}", typeof(T).Name);
            throw new ExternalServiceException("The AI service returned an unexpected response. Please try again.", ex);
        }
    }

    public int MaxImages => 8;

    private static BetaContentBlockParam ToBlock(LlmPart part) => part switch
    {
        LlmJpeg img => new BetaImageBlockParam
        {
            Source = new BetaBase64ImageSource { Data = Convert.ToBase64String(img.Bytes), MediaType = MediaType.ImageJpeg },
        },
        LlmText t => new BetaTextBlockParam { Text = t.Text },
        _ => throw new ArgumentOutOfRangeException(nameof(part)),
    };
}
