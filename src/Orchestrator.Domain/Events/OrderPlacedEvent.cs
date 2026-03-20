using System;

namespace Orchestrator.Domain.Events;

public class OrderPlacedEvent
{
    public string OrderId { get; set; } = string.Empty;
    public string UserId { get; set; } = string.Empty;
    public decimal TotalAmount { get; set; }
    public DateTime PlacedAt { get; set; }
}