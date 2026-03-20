using MongoDB.Driver;
using Orchestrator.Domain;

namespace Orchestrator.Infrastructure;

public class MongoDbContext
{
    private readonly IMongoDatabase _database;

    public MongoDbContext(string connectionString, string databaseName)
    {
        var client = new MongoClient(connectionString);
        _database = client.GetDatabase(databaseName);
    }

    public IMongoCollection<LogEntry> Logs => _database.GetCollection<LogEntry>("Logs");
}