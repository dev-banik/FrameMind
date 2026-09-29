using FrameMind.Domain.Common;

namespace FrameMind.Domain.Entities;

public class Project : Entity
{
    private Project() { }

    public Project(Guid userId, string name)
    {
        UserId = userId;
        Rename(name);
    }

    public Guid UserId { get; private set; }
    public string Name { get; private set; } = "";

    public ICollection<Chat> Chats { get; private set; } = new List<Chat>();

    public void Rename(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) throw new DomainException("Project name is required.");
        Name = name.Trim();
    }
}
