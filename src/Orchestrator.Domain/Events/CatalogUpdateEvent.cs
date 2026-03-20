using System;

namespace Orchestrator.Domain.Events;

public class CatalogUpdateEvent
{
    public string ProductId { get; set; } = string.Empty;
    public int Quantity { get; set; }
    public DateTime UpdatedAt { get; set; }
}