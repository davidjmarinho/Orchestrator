using Xunit;
using Moq;
using Mongo2Go;
using Orchestrator.Infrastructure;
using Orchestrator.Application;
using Orchestrator.Domain;
using Orchestrator.Domain.Events;

namespace Orchestrator.IntegrationTests;

public class OrchestratorFlowIntegrationTests : IDisposable
{
    private readonly MongoDbRunner _runner;
    private readonly MongoDbContext _context;
    private readonly LogRepository _repository;
    private readonly Mock<IMessageBus> _mockMessageBus;

    public OrchestratorFlowIntegrationTests()
    {
        _runner = MongoDbRunner.Start();
        _context = new MongoDbContext(_runner.ConnectionString, "orchestrator-test");
        _repository = new LogRepository(_context);
        _mockMessageBus = new Mock<IMessageBus>();
    }

    [Fact]
    public async Task UserCreatedFlow_ShouldLogAndPublishNotification()
    {
        // Arrange
        var handler = new UserCreatedEventHandler(_mockMessageBus.Object, _repository);
        var userEvent = new UserCreatedEvent
        {
            UserId = "user123",
            Email = "test@example.com",
            CreatedAt = DateTime.UtcNow
        };

        // Act
        await handler.HandleAsync(userEvent);

        // Assert - Verificar logs no MongoDB
        var logs = await _repository.GetAllAsync();
        Assert.Equal(2, logs.Count); // RECEIVED e PROCESSED
        Assert.Contains(logs, l => l.Status == "RECEIVED");
        Assert.Contains(logs, l => l.Status == "PROCESSED");

        // Assert - Verificar publicação
        _mockMessageBus.Verify(x => x.PublishAsync(It.IsAny<NotificationEvent>()), Times.Once);
    }

    [Fact]
    public async Task OrderPlacedFlow_ShouldLogAndPublishPaymentRequest()
    {
        // Arrange
        var handler = new OrderPlacedEventHandler(_mockMessageBus.Object, _repository);
        var orderEvent = new OrderPlacedEvent
        {
            OrderId = "order123",
            UserId = "user123",
            TotalAmount = 100.00m,
            PlacedAt = DateTime.UtcNow
        };

        // Act
        await handler.HandleAsync(orderEvent);

        // Assert - Verificar logs
        var logs = await _repository.GetAllAsync();
        Assert.Equal(2, logs.Count);
        Assert.All(logs, log => Assert.Equal("OrderPlacedEvent", log.EventName));

        // Assert - Verificar publicação
        _mockMessageBus.Verify(x => x.PublishAsync(It.IsAny<PaymentRequestEvent>()), Times.Once);
    }

    [Fact]
    public async Task PaymentProcessedFlow_ShouldLogAndPublishMultipleEvents()
    {
        // Arrange
        var handler = new PaymentProcessedEventHandler(_mockMessageBus.Object, _repository);
        var paymentEvent = new PaymentProcessedEvent
        {
            PaymentId = "payment123",
            OrderId = "order123",
            IsSuccessful = true,
            ProcessedAt = DateTime.UtcNow,
            ProductId = "product123",
            UserId = "user123"
        };

        // Act
        await handler.HandleAsync(paymentEvent);

        // Assert - Verificar logs
        var logs = await _repository.GetAllAsync();
        Assert.Equal(2, logs.Count);
        Assert.Contains(logs, l => l.Status == "RECEIVED");
        Assert.Contains(logs, l => l.Status == "PROCESSED");

        // Assert - Verificar publicações
        _mockMessageBus.Verify(x => x.PublishAsync(It.IsAny<CatalogUpdateEvent>()), Times.Once);
        _mockMessageBus.Verify(x => x.PublishAsync(It.IsAny<NotificationEvent>()), Times.Once);
    }

    [Fact]
    public async Task CompleteFlow_ShouldOrchestrateThroughAllSteps()
    {
        // Arrange
        var orderHandler = new OrderPlacedEventHandler(_mockMessageBus.Object, _repository);
        var paymentHandler = new PaymentProcessedEventHandler(_mockMessageBus.Object, _repository);

        var orderEvent = new OrderPlacedEvent
        {
            OrderId = "order123",
            UserId = "user123",
            TotalAmount = 100.00m,
            PlacedAt = DateTime.UtcNow
        };

        var paymentEvent = new PaymentProcessedEvent
        {
            PaymentId = "payment123",
            OrderId = "order123",
            IsSuccessful = true,
            ProcessedAt = DateTime.UtcNow,
            ProductId = "product123",
            UserId = "user123"
        };

        // Act
        await orderHandler.HandleAsync(orderEvent);
        await paymentHandler.HandleAsync(paymentEvent);

        // Assert
        var logs = await _repository.GetAllAsync();
        Assert.Equal(4, logs.Count); // 2 para order + 2 para payment
        
        // Verificar sequência de eventos
        Assert.Contains(logs, l => l.EventName == "OrderPlacedEvent" && l.Status == "RECEIVED");
        Assert.Contains(logs, l => l.EventName == "OrderPlacedEvent" && l.Status == "PROCESSED");
        Assert.Contains(logs, l => l.EventName == "PaymentProcessedEvent" && l.Status == "RECEIVED");
        Assert.Contains(logs, l => l.EventName == "PaymentProcessedEvent" && l.Status == "PROCESSED");
    }

    public void Dispose()
    {
        _runner?.Dispose();
    }
}
