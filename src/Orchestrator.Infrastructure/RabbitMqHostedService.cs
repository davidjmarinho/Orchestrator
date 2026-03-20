using Microsoft.Extensions.Hosting;
using RabbitMQ.Client;
using RabbitMQ.Client.Events;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Orchestrator.Infrastructure;

public class RabbitMqHostedService : IHostedService
{
    private readonly RabbitMqConnectionFactory _connectionFactory;
    private IConnection _connection;
    private IModel _channel;

    public RabbitMqHostedService(RabbitMqConnectionFactory connectionFactory)
    {
        _connectionFactory = connectionFactory;
        _connection = null!; // Initialized in StartAsync
        _channel = null!; // Initialized in StartAsync
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        _connection = _connectionFactory.CreateConnection();
        _channel = _connection.CreateModel();

        _channel.QueueDeclare(queue: "orchestrator-queue",
                              durable: true,
                              exclusive: false,
                              autoDelete: false,
                              arguments: null);

        var consumer = new EventingBasicConsumer(_channel);
        consumer.Received += (model, ea) =>
        {
            var body = ea.Body.ToArray();
            var message = Encoding.UTF8.GetString(body);
            // Process the message
        };

        _channel.BasicConsume(queue: "orchestrator-queue",
                              autoAck: true,
                              consumer: consumer);

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        _channel?.Close();
        _connection?.Close();
        return Task.CompletedTask;
    }
}