using System;

namespace Orchestrator.Domain.Events;

public class UserCreatedEvent
{
    public string UserId { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
}