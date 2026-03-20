using Orchestrator.Domain;
using Orchestrator.Domain.Events;
using System;
using System.Threading.Tasks;

namespace Orchestrator.Application;

public class PaymentProcessedEventHandler : IEventHandler<PaymentProcessedEvent>
{
    private readonly IMessageBus _messageBus;
    private readonly ILogRepository _logRepository;

    public PaymentProcessedEventHandler(IMessageBus messageBus, ILogRepository logRepository)
    {
        _messageBus = messageBus;
        _logRepository = logRepository;
    }

    public async Task HandleAsync(PaymentProcessedEvent @event)
    {
        var receivedLog = new LogEntry
        {
            Id = Guid.NewGuid().ToString(),
            EventName = nameof(PaymentProcessedEvent),
            Payload = System.Text.Json.JsonSerializer.Serialize(@event),
            Status = "RECEIVED",
            CreatedAt = DateTime.UtcNow
        };

        await _logRepository.SaveAsync(receivedLog);

        try
        {
            // Orchestrate flow
            await _messageBus.PublishAsync(new CatalogUpdateEvent { ProductId = @event.ProductId });
            await _messageBus.PublishAsync(new NotificationEvent { UserId = @event.UserId });

            var processedLog = new LogEntry
            {
                Id = Guid.NewGuid().ToString(),
                EventName = nameof(PaymentProcessedEvent),
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
                EventName = nameof(PaymentProcessedEvent),
                Payload = System.Text.Json.JsonSerializer.Serialize(@event),
                Status = "FAILED",
                Error = ex.Message,
                CreatedAt = DateTime.UtcNow
            };
            await _logRepository.SaveAsync(failedLog);
        }
    }
}