namespace Orchestrator.Domain;

/// <summary>
/// Abstração para publicação de eventos em filas SQS.
/// Separada de IMessageBus (RabbitMQ) — cada interface tem um broker.
///
/// Implementações:
///   SqsPublisher  — AWSSDK.SQS; aponta para LocalStack ou AWS real via env var
/// </summary>
public interface ISqsMessageBus
{
    /// <param name="queueUrl">URL completa da fila SQS.
    /// LocalStack: http://localstack:4566/000000000000/nome-da-fila
    /// AWS real:   https://sqs.us-east-1.amazonaws.com/123456789/nome-da-fila
    /// </param>
    Task PublishAsync<T>(string queueUrl, T message);
}
