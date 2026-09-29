namespace FrameMind.Application.Common;

public class NotFoundException(string resource, object key)
    : Exception($"{resource} '{key}' was not found.");

/// <summary>Action is not permitted on the caller's plan (HTTP 403).</summary>
public class PlanLimitException(string message) : Exception(message);

/// <summary>Daily quota exhausted (HTTP 429).</summary>
public class QuotaExceededException(string message) : Exception(message);

/// <summary>Upstream AI/media provider failed (HTTP 502).</summary>
public class ExternalServiceException(string message, Exception? inner = null) : Exception(message, inner);
