using Orchestrator.Domain;
using Orchestrator.Domain.Events;
using System;
using System.Threading.Tasks;

namespace Orchestrator.Application;

public class OrderPlacedEventHandler : IEventHandler<OrderPlacedEvent>
{
    private readonly IMessageBus _messageBus;
    private readonly ILogRepository _logRepository;

    public OrderPlacedEventHandler(IMessageBus messageBus, ILogRepository logRepository)
    {
        _messageBus = messageBus;
        _logRepository = logRepository;
    }

    public async Task HandleAsync(OrderPlacedEvent @event)
    {
        var receivedLog = new LogEntry
        {
            Id = Guid.NewGuid().ToString(),
            EventName = nameof(OrderPlacedEvent),
            Payload = System.Text.Json.JsonSerializer.Serialize(@event),
            Status = "RECEIVED",
            CreatedAt = DateTime.UtcNow
        };

        await _logRepository.SaveAsync(receivedLog);

        try
        {
            // Orchestrate flow
            await _messageBus.PublishAsync(new PaymentRequestEvent { OrderId = @event.OrderId });

            var processedLog = new LogEntry
            {
                Id = Guid.NewGuid().ToString(),
                EventName = nameof(OrderPlacedEvent),
                Payload = System.Text.Json.JsonSerializer.Serialize(@event),
                Status = "PROCESSED",
                CreatedAt = DateTime.UtcNow
            };
            await _logRepository.SaveAsync(processedLog);
        }
        catch (Exception ex)
        {
            var failedLog = new LogEntry
            {
                Id = Guid.NewGuid().ToString(),
                EventName = nameof(OrderPlacedEvent),
                Payload = System.Text.Json.JsonSerializer.Serialize(@event),
                Status = "FAILED",
                Error = ex.Message,
                CreatedAt = DateTime.UtcNow
            };
            await _logRepository.SaveAsync(failedLog);
        }
    }
}