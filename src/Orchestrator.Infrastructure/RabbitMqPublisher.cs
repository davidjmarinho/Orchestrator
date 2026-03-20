using RabbitMQ.Client;
using System.Text;
using Orchestrator.Domain;
using System.Text.Json;

namespace Orchestrator.Infrastructure;

public class RabbitMqPublisher : IMessageBus
{
    private readonly ConnectionFactory _factory;

    public RabbitMqPublisher()
    {
        _factory = new ConnectionFactory()
        {
            HostName = Environment.GetEnvironmentVariable("RABBITMQ_HOST"),
            UserName = Environment.GetEnvironmentVariable("RABBITMQ_USER"),
            Password = Environment.GetEnvironmentVariable("RABBITMQ_PASS")
        };
    }

    public Task PublishAsync(string queue, object message)
    {
        using var connection = _factory.CreateConnection(); // Synchronous method
        using var channel = connection.CreateModel(); // Synchronous method

        channel.QueueDeclare(queue, durable: false, exclusive: false, autoDelete: false, arguments: null);

        var body = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(message));

        channel.BasicPublish(exchange: "", routingKey: queue, basicProperties: null, body: body); // Synchronous method

        Console.WriteLine($"[RabbitMQ] Published → {queue}");

        return Task.CompletedTask;
    }

    public Task PublishAsync<T>(T message)
    {
        throw new NotImplementedException();
    }

    public Task SubscribeAsync<T>(string queueName, Func<T, Task> onMessage)
    {
        throw new NotImplementedException();
    }
}