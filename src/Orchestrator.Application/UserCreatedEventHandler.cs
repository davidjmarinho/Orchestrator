using Orchestrator.Domain;
using Orchestrator.Domain.Events;

namespace Orchestrator.Application;

public class UserCreatedEventHandler : IEventHandler<UserCreatedEvent>
{
    private readonly IMessageBus    _messageBus;
    private readonly ISqsMessageBus _sqsBus;
    private readonly ILogRepository _logRepository;

    // URLs das filas SQS (LocalStack ou AWS real)
    private static readonly string SqsUserCreatedQueueUrl =
        Environment.GetEnvironmentVariable("SQS_USER_CREATED_QUEUE_URL")
        ?? "http://localstack:4566/000000000000/user-created-queue";

    public UserCreatedEventHandler(
        IMessageBus    messageBus,
        ISqsMessageBus sqsBus,
        ILogRepository logRepository)
    {
        _messageBus    = messageBus;
        _sqsBus        = sqsBus;
        _logRepository = logRepository;
    }

    public async Task HandleAsync(UserCreatedEvent @event)
    {
        var receivedLog = new LogEntry
        {
            Id        = Guid.NewGuid().ToString(),
            EventName = nameof(UserCreatedEvent),
            Payload   = System.Text.Json.JsonSerializer.Serialize(@event),
            Status    = "RECEIVED",
            CreatedAt = DateTime.UtcNow
        };
        await _logRepository.SaveAsync(receivedLog);

        try
        {
            // Fluxo RabbitMQ (comportamento original)
            await _messageBus.PublishAsync(new NotificationEvent { UserId = @event.UserId });

            // Publica no SQS para a Lambda de notificações
            // Mapeia para o shape esperado pela NotificationsLambda
            await _sqsBus.PublishAsync(SqsUserCreatedQueueUrl, new
            {
                UserId    = @event.UserId,
                UserName  = @event.Email, // Orchestrator não tem UserName — usa email como fallback
                UserEmail = @event.Email,
                Email     = @event.Email,
                CreatedAt = @event.CreatedAt
            });

            var processedLog = new LogEntry
            {
                Id        = Guid.NewGuid().ToString(),
                EventName = nameof(UserCreatedEvent),
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
                EventName = nameof(UserCreatedEvent),
                Payload   = System.Text.Json.JsonSerializer.Serialize(@event),
                Status    = "FAILED",
                Error     = ex.Message,
                CreatedAt = DateTime.UtcNow
            };
            await _logRepository.SaveAsync(failedLog);
        }
    }
}
