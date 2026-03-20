using System;
using System.Threading.Tasks;

namespace Orchestrator.Domain;

public interface IMessageBus
{
    Task PublishAsync<T>(T message);
    Task SubscribeAsync<T>(string queueName, Func<T, Task> onMessage);
}