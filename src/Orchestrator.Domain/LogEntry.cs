using System;

namespace Orchestrator.Domain;

public class LogEntry
{
    public string Id { get; set; } = string.Empty;
    public string EventName { get; set; } = string.Empty;
    public string Payload { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public string Error { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}