using System;

namespace Orchestrator.Domain.Events;

public class NotificationEvent
{
    public string UserId { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public DateTime SentAt { get; set; }
}