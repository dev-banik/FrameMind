namespace FrameMind.Domain.Common;

public abstract class Entity
{
    public Guid Id { get; protected set; } = Guid.NewGuid();
    public DateTime CreatedAt { get; protected set; } = DateTime.UtcNow;
}

/// <summary>Thrown when an operation would violate a domain invariant.</summary>
public class DomainException(string message) : Exception(message);
