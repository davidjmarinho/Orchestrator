using Amazon.Runtime;
using Amazon.SQS;
using Amazon.SQS.Model;
using Orchestrator.Domain;
using System.Text.Json;

namespace Orchestrator.Infrastructure;

/// <summary>
/// Publica mensagens em filas SQS.
///
/// Variáveis de ambiente lidas:
///   AWS_ENDPOINT_URL       — URL do endpoint (LocalStack ou vazio para AWS real)
///   AWS_DEFAULT_REGION     — region (padrão: us-east-1)
///   AWS_ACCESS_KEY_ID      — access key (padrão: "test" para LocalStack)
///   AWS_SECRET_ACCESS_KEY  — secret key (padrão: "test" para LocalStack)
///
/// Para trocar LocalStack → AWS real:
///   Remova AWS_ENDPOINT_URL do ambiente.
///   O SDK usará o endpoint padrão da AWS para a region configurada.
/// </summary>
public class SqsPublisher : ISqsMessageBus
{
    private readonly IAmazonSQS _client;

    public SqsPublisher()
    {
        var endpointUrl = Environment.GetEnvironmentVariable("AWS_ENDPOINT_URL");
        var region      = Environment.GetEnvironmentVariable("AWS_DEFAULT_REGION") ?? "us-east-1";
        var accessKey   = Environment.GetEnvironmentVariable("AWS_ACCESS_KEY_ID")     ?? "test";
        var secretKey   = Environment.GetEnvironmentVariable("AWS_SECRET_ACCESS_KEY") ?? "test";

        var config = new AmazonSQSConfig { AuthenticationRegion = region };

        if (!string.IsNullOrWhiteSpace(endpointUrl))
            config.ServiceURL = endpointUrl; // LocalStack

        _client = new AmazonSQSClient(
            new BasicAWSCredentials(accessKey, secretKey),
            config);
    }

    public async Task PublishAsync<T>(string queueUrl, T message)
    {
        var body = JsonSerializer.Serialize(message);

        var response = await _client.SendMessageAsync(new SendMessageRequest
        {
            QueueUrl    = queueUrl,
            MessageBody = body
        });

        var queueName = queueUrl.Split('/').Last();
        Console.WriteLine($"[SQS] ✅ Published → {queueName} (MsgId: {response.MessageId})");
    }
}
