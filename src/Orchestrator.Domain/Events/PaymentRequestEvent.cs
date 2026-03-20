using System;

namespace Orchestrator.Domain.Events;

public class PaymentRequestEvent
{
    public string OrderId { get; set; } = string.Empty;
    public decimal Amount { get; set; }
    public DateTime RequestedAt { get; set; }
}