using FluentValidation;
using FrameMind.Application.Common;
using FrameMind.Domain.Common;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;

namespace FrameMind.Api.Infrastructure;

/// <summary>Maps application exceptions to RFC 7807 problem responses.</summary>
public sealed class ProblemExceptionHandler(IProblemDetailsService problems, ILogger<ProblemExceptionHandler> logger)
    : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext http, Exception exception, CancellationToken ct)
    {
        var (status, title, detail) = exception switch
        {
            ValidationException => (StatusCodes.Status400BadRequest, "Validation failed", exception.Message),
            DomainException => (StatusCodes.Status409Conflict, "Invalid state", exception.Message),
            NotFoundException => (StatusCodes.Status404NotFound, "Not found", exception.Message),
            PlanLimitException => (StatusCodes.Status403Forbidden, "Upgrade required", exception.Message),
            QuotaExceededException => (StatusCodes.Status429TooManyRequests, "Daily limit reached", exception.Message),
            ExternalServiceException => (StatusCodes.Status502BadGateway, "Upstream service error", exception.Message),
            UnauthorizedAccessException => (StatusCodes.Status401Unauthorized, "Unauthorized", "Sign in again."),
            _ => (StatusCodes.Status500InternalServerError, "Unexpected error", "Something went wrong. Please try again."),
        };

        if (status >= 500 && exception is not ExternalServiceException)
            logger.LogError(exception, "Unhandled exception for {Path}", http.Request.Path);

        var problem = new ProblemDetails { Status = status, Title = title, Detail = detail };
        if (exception is ValidationException { Errors: var errors } && errors.Any())
        {
            problem.Detail = errors.First().ErrorMessage;
            problem.Extensions["errors"] = errors
                .GroupBy(e => ToCamel(e.PropertyName))
                .ToDictionary(g => g.Key, g => g.Select(e => e.ErrorMessage).ToArray());
        }

        http.Response.StatusCode = status;
        return await problems.TryWriteAsync(new ProblemDetailsContext { HttpContext = http, ProblemDetails = problem, Exception = exception });
    }

    private static string ToCamel(string name) =>
        string.Join('.', name.Split('.').Select(p => p.Length == 0 ? p : char.ToLowerInvariant(p[0]) + p[1..]));
}
