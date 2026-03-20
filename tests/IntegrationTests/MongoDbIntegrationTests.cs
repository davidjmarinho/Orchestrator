using Xunit;
using Mongo2Go;
using Orchestrator.Infrastructure;
using Orchestrator.Domain;

namespace Orchestrator.IntegrationTests;

public class MongoDbIntegrationTests : IDisposable
{
    private readonly MongoDbRunner _runner;
    private readonly MongoDbContext _context;
    private readonly LogRepository _repository;

    public MongoDbIntegrationTests()
    {
        _runner = MongoDbRunner.Start();
        _context = new MongoDbContext(_runner.ConnectionString, "orchestrator-test");
        _repository = new LogRepository(_context);
    }

    [Fact]
    public async Task SaveAsync_ShouldPersistLogEntry()
    {
        // Arrange
        var logEntry = new LogEntry
        {
            Id = Guid.NewGuid().ToString(),
            EventName = "TestEvent",
            Payload = "{\"test\":\"data\"}",
            Status = "PROCESSED",
            CreatedAt = DateTime.UtcNow
        };

        // Act
        await _repository.SaveAsync(logEntry);
        var logs = await _repository.GetAllAsync();

        // Assert
        Assert.Single(logs);
        Assert.Equal(logEntry.Id, logs[0].Id);
        Assert.Equal(logEntry.EventName, logs[0].EventName);
        Assert.Equal(logEntry.Status, logs[0].Status);
    }

    [Fact]
    public async Task SaveAsync_ShouldPersistMultipleLogs()
    {
        // Arrange
        var log1 = new LogEntry
        {
            Id = Guid.NewGuid().ToString(),
            EventName = "Event1",
            Payload = "{}",
            Status = "RECEIVED",
            CreatedAt = DateTime.UtcNow
        };

        var log2 = new LogEntry
        {
            Id = Guid.NewGuid().ToString(),
            EventName = "Event2",
            Payload = "{}",
            Status = "PROCESSED",
            CreatedAt = DateTime.UtcNow
        };

        // Act
        await _repository.SaveAsync(log1);
        await _repository.SaveAsync(log2);
        var logs = await _repository.GetAllAsync();

        // Assert
        Assert.Equal(2, logs.Count);
    }

    [Fact]
    public async Task SaveAsync_ShouldHandleErrorStatus()
    {
        // Arrange
        var logEntry = new LogEntry
        {
            Id = Guid.NewGuid().ToString(),
            EventName = "FailedEvent",
            Payload = "{}",
            Status = "FAILED",
            Error = "Test error message",
            CreatedAt = DateTime.UtcNow
        };

        // Act
        await _repository.SaveAsync(logEntry);
        var logs = await _repository.GetAllAsync();

        // Assert
        Assert.Single(logs);
        Assert.Equal("FAILED", logs[0].Status);
        Assert.Equal("Test error message", logs[0].Error);
    }

    public void Dispose()
    {
        _runner?.Dispose();
    }
}
