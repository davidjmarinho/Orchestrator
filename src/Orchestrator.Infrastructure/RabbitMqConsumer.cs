#nullable enable

using Orchestrator.Domain.Events;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.DependencyInjection;
using RabbitMQ.Client;
using RabbitMQ.Client.Events;
using System.Text;
using System.Text.Json;
using Orchestrator.Domain;

namespace Orchestrator.Infrastructure;

public class RabbitMqConsumer : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private IConnection? _connection; // Nullable
    private IModel? _channel; // Nullable

    public RabbitMqConsumer(IServiceProvider serviceProvider)
    {
        _serviceProvider = serviceProvider ?? throw new ArgumentNullException(nameof(serviceProvider));
    }

    protected override Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var factory = new ConnectionFactory()
        {
            HostName = Environment.GetEnvironmentVariable("RABBITMQ_HOST"),
            UserName = Environment.GetEnvironmentVariable("RABBITMQ_USER"),
            Password = Environment.GetEnvironmentVariable("RABBITMQ_PASS")
        };

        _connection = factory.CreateConnection();
        _channel = _connection.CreateModel();

        Consume<OrderPlacedEvent>("order-placed");
        Consume<PaymentProcessedEvent>("payment-processed");

        return Task.CompletedTask;
    }

    private void Consume<T>(string queue)
    {
        _channel?.QueueDeclare(queue, durable: true, exclusive: false, autoDelete: false, arguments: null);

        var consumer = new EventingBasicConsumer(_channel);
        consumer.Received += async (model, ea) =>
        {
            var body = ea.Body.ToArray();
            var message = Encoding.UTF8.GetString(body);
            var eventObj = JsonSerializer.Deserialize<T>(message);

            if (eventObj == null)
            {
                // Log or handle null case
                return;
            }

            using var scope = _serviceProvider.CreateScope();
            var handler = scope.ServiceProvider.GetRequiredService<IEventHandler<T>>();
            await handler.HandleAsync(eventObj);
        };

        _channel?.BasicConsume(queue, autoAck: true, consumer: consumer);
    }

    public override void Dispose()
    {
        _channel?.Close();
        _connection?.Close();
        _channel?.Dispose();
        _connection?.Dispose();
        base.Dispose();
    }
}