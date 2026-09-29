using System.Net.Http.Json;
using System.Text.Json;
using FrameMind.Application.Common;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FrameMind.Infrastructure.AI;

/// <summary>
/// Free, keyless LLM via a local Ollama server. Uses Ollama structured outputs
/// (<c>format</c> = JSON schema) and sends keyframes as base64 images.
/// </summary>
public sealed class OllamaJsonClient(
    IHttpClientFactory httpFactory, IOptions<LlmOptions> options, ILogger<OllamaJsonClient> logger) : ILlmJsonClient
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private readonly OllamaOptions _opt = options.Value.Ollama;

    public int MaxImages => _opt.MaxImages;

    public async Task<T> CompleteAsync<T>(
        string system, IReadOnlyList<LlmPart> parts, string jsonSchema, LlmEffort effort, CancellationToken ct)
    {
        var text = string.Join("\n\n", parts.OfType<LlmText>().Select(p => p.Text));
        var images = parts.OfType<LlmJpeg>().Take(MaxImages).Select(p => Convert.ToBase64String(p.Bytes)).ToArray();

        var body = new Dictionary<string, object?>
        {
            ["model"] = _opt.Model,
            ["stream"] = false,
            ["format"] = JsonSerializer.Deserialize<JsonElement>(jsonSchema),
            ["keep_alive"] = "30m",
            ["options"] = new { temperature = effort == LlmEffort.Low ? 0.6 : 0.8, num_ctx = _opt.ContextLength },
            ["messages"] = new object[]
            {
                new { role = "system", content = system + "\n\nRespond with JSON only, matching the provided schema." },
                images.Length > 0
                    ? new { role = "user", content = text, images }
                    : (object)new { role = "user", content = text },
            },
        };

        HttpResponseMessage response;
        try
        {
            response = await httpFactory.CreateClient("ollama")
                .PostAsJsonAsync($"{_opt.BaseUrl.TrimEnd('/')}/api/chat", body, ct);
        }
        catch (HttpRequestException ex)
        {
            throw new ExternalServiceException(
                $"The local AI model isn't reachable at {_opt.BaseUrl}. Is Ollama running?", ex);
        }
        catch (TaskCanceledException ex) when (!ct.IsCancellationRequested)
        {
            throw new ExternalServiceException("The local AI model took too long to respond. Try a shorter duration.", ex);
        }

        using (response)
        {
            var raw = await response.Content.ReadAsStringAsync(ct);
            if (!response.IsSuccessStatusCode)
            {
                logger.LogError("Ollama returned {Status}: {Body}", (int)response.StatusCode, raw.Length > 500 ? raw[..500] : raw);
                throw new ExternalServiceException(raw.Contains("not found", StringComparison.OrdinalIgnoreCase)
                    ? $"The AI model '{_opt.Model}' isn't downloaded yet. Run: ollama pull {_opt.Model}"
                    : "The local AI model returned an error.");
            }

            try
            {
                using var doc = JsonDocument.Parse(raw);
                var content = doc.RootElement.GetProperty("message").GetProperty("content").GetString() ?? "";
                return JsonSerializer.Deserialize<T>(StripFences(content), Json) ?? throw new JsonException("Empty response.");
            }
            catch (Exception ex) when (ex is JsonException or KeyNotFoundException or InvalidOperationException)
            {
                logger.LogError(ex, "Ollama returned JSON that did not match {Type}", typeof(T).Name);
                throw new ExternalServiceException("The AI returned an unexpected response. Please try again.", ex);
            }
        }
    }

    /// <summary>Small models occasionally wrap JSON in markdown fences despite the format constraint.</summary>
    private static string StripFences(string s)
    {
        s = s.Trim();
        if (!s.StartsWith("```")) return s;
        var start = s.IndexOf('\n');
        var end = s.LastIndexOf("```", StringComparison.Ordinal);
        return start >= 0 && end > start ? s[(start + 1)..end] : s;
    }
}
