using System.Collections.Generic;
using System.Threading.Tasks;

namespace Orchestrator.Domain;

public interface ILogRepository
{
    Task SaveAsync(LogEntry log);
    Task<List<LogEntry>> GetAllAsync();
}