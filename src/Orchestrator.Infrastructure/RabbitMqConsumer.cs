#nullable enable

using Orchestrator.Domain.Events;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.DependencyInjection;
using RabbitMQ.Client;
using RabbitMQ.Client.Events;
using System.Text;
using System.Text.Json;
using System.Linq;
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

        Consume<UserCreatedEvent>("user-created");
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

            // Try to deserialize directly first (plain JSON)
            T? eventObj = default;
            try
            {
                eventObj = JsonSerializer.Deserialize<T>(message, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });
            }
            catch { /* Not plain JSON, try MassTransit envelope */ }

            // If direct deserialization failed or resulted in empty object, try MassTransit envelope
            if (eventObj == null || IsEmpty(eventObj))
            {
                try
                {
                    using var doc = JsonDocument.Parse(message);
                    if (doc.RootElement.TryGetProperty("message", out var msgElement))
                    {
                        eventObj = JsonSerializer.Deserialize<T>(msgElement.GetRawText(), new JsonSerializerOptions
                        {
                            PropertyNameCaseInsensitive = true
                        });
                    }
                }
                catch { /* ignore parse errors */ }
            }

            if (eventObj == null)
            {
                Console.WriteLine($"[Orchestrator] ⚠️ Could not deserialize message from queue '{queue}': {message[..Math.Min(200, message.Length)]}");
                return;
            }

            Console.WriteLine($"[Orchestrator] 📨 Event received from queue '{queue}': {typeof(T).Name}");

            using var scope = _serviceProvider.CreateScope();
            var handler = scope.ServiceProvider.GetRequiredService<IEventHandler<T>>();
            await handler.HandleAsync(eventObj);

            Console.WriteLine($"[Orchestrator] ✅ Event handled: {typeof(T).Name}");
        };

        _channel?.BasicConsume(queue, autoAck: true, consumer: consumer);
        Console.WriteLine($"[Orchestrator] 🐇 Listening on queue: '{queue}'");
    }

    private static bool IsEmpty<TObj>(TObj obj)
    {
        if (obj == null) return true;
        // Check if all string properties are empty (indicates failed deserialization)
        var props = typeof(TObj).GetProperties();
        return props.Length > 0 && props.All(p =>
        {
            var val = p.GetValue(obj);
            return val == null || (val is string s && string.IsNullOrEmpty(s)) || val.Equals(GetDefault(p.PropertyType));
        });
    }

    private static object? GetDefault(Type type)
    {
        return type.IsValueType ? Activator.CreateInstance(type) : null;
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