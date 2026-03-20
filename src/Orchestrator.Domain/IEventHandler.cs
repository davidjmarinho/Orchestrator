using System.Threading.Tasks;

namespace Orchestrator.Domain;

public interface IEventHandler<T>
{
    Task HandleAsync(T @event);
}