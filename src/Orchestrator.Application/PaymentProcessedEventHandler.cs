using Orchestrator.Domain;
using Orchestrator.Domain.Events;

namespace Orchestrator.Application;

public class PaymentProcessedEventHandler : IEventHandler<PaymentProcessedEvent>
{
    private readonly IMessageBus    _messageBus;
    private readonly ISqsMessageBus _sqsBus;
    private readonly ILogRepository _logRepository;

    // URL da fila SQS (LocalStack ou AWS real)
    private static readonly string SqsPaymentProcessedQueueUrl =
        Environment.GetEnvironmentVariable("SQS_PAYMENT_PROCESSED_QUEUE_URL")
        ?? "http://localstack:4566/000000000000/payment-processed-queue";

    public PaymentProcessedEventHandler(
        IMessageBus    messageBus,
        ISqsMessageBus sqsBus,
        ILogRepository logRepository)
    {
        _messageBus    = messageBus;
        _sqsBus        = sqsBus;
        _logRepository = logRepository;
    }

    public async Task HandleAsync(PaymentProcessedEvent @event)
    {
        var receivedLog = new LogEntry
        {
            Id        = Guid.NewGuid().ToString(),
            EventName = nameof(PaymentProcessedEvent),
            Payload   = System.Text.Json.JsonSerializer.Serialize(@event),
            Status    = "RECEIVED",
            CreatedAt = DateTime.UtcNow
        };
        await _logRepository.SaveAsync(receivedLog);

        try
        {
            // Fluxo RabbitMQ (comportamento original)
            await _messageBus.PublishAsync(new CatalogUpdateEvent { ProductId = @event.ProductId });
            await _messageBus.PublishAsync(new NotificationEvent  { UserId    = @event.UserId   });

            // Publica no SQS para a Lambda de notificações
            // Mapeia IsSuccessful (bool) → Status (string) que a Lambda entende
            await _sqsBus.PublishAsync(SqsPaymentProcessedQueueUrl, new
            {
                PaymentId   = @event.PaymentId,
                UserId      = @event.UserId,
                UserEmail   = "",             // Orchestrator não tem o e-mail do usuário
                Amount      = 0m,             // Orchestrator não tem o valor do pagamento
                Status      = @event.IsSuccessful ? "Approved" : "Declined",
                IsSuccessful = @event.IsSuccessful,
                ProcessedAt = @event.ProcessedAt
            });

            var processedLog = new LogEntry
            {
                Id        = Guid.NewGuid().ToString(),
                EventName = nameof(PaymentProcessedEvent),
                Payload   = System.Text.Json.JsonSerializer.Serialize(@event),
                Status    = "PROCESSED",
                CreatedAt = DateTime.UtcNow
            };
            await _logRepository.SaveAsync(processedLog);
        }
        catch (Exception ex)
        {
            var failedLog = new LogEntry
            {
                Id        = Guid.NewGuid().ToString(),
                EventName = nameof(PaymentProcessedEvent),
                Payload   = System.Text.Json.JsonSerializer.Serialize(@event),
                Status    = "FAILED",
                Error     = ex.Message,
                CreatedAt = DateTime.UtcNow
            };
            await _logRepository.SaveAsync(failedLog);
        }
    }
}
