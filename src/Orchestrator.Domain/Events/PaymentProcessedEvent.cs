using System;

namespace Orchestrator.Domain.Events;

public class PaymentProcessedEvent
{
    public string PaymentId { get; set; } = string.Empty;
    public string OrderId { get; set; } = string.Empty;
    public bool IsSuccessful { get; set; }
    public DateTime ProcessedAt { get; set; }
    public string ProductId { get; set; } = string.Empty;
    public string UserId { get; set; } = string.Empty;
}