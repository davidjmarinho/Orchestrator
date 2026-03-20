using MongoDB.Driver;
using System.Collections.Generic;
using System.Threading.Tasks;
using Orchestrator.Domain;

namespace Orchestrator.Infrastructure;

public class LogRepository : ILogRepository
{
    private readonly IMongoCollection<LogEntry> _collection;

    public LogRepository(MongoDbContext context)
    {
        _collection = context.Logs;
    }

    public Task SaveAsync(LogEntry log)
    {
        return _collection.InsertOneAsync(log);
    }

    public async Task<List<LogEntry>> GetAllAsync()
    {
        return await _collection.Find(_ => true).ToListAsync();
    }
}