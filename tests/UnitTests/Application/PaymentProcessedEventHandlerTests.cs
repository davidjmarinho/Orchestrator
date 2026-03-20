using Moq;
using Xunit;
using Orchestrator.Application;
using Orchestrator.Domain;
using Orchestrator.Domain.Events;

namespace Orchestrator.UnitTests.Application;

public class PaymentProcessedEventHandlerTests
{
    private readonly Mock<IMessageBus> _mockMessageBus;
    private readonly Mock<ILogRepository> _mockLogRepository;
    private readonly PaymentProcessedEventHandler _handler;

    public PaymentProcessedEventHandlerTests()
    {
        _mockMessageBus = new Mock<IMessageBus>();
        _mockLogRepository = new Mock<ILogRepository>();
        _handler = new PaymentProcessedEventHandler(_mockMessageBus.Object, _mockLogRepository.Object);
    }

    [Fact]
    public async Task Handle_ShouldLogReceivedEvent()
    {
        // Arrange
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
        await _handler.HandleAsync(paymentEvent);

        // Assert
        _mockLogRepository.Verify(x => x.SaveAsync(It.Is<LogEntry>(log =>
            log.EventName == "PaymentProcessedEvent" &&
            log.Status == "RECEIVED"
        )), Times.Once);
    }

    [Fact]
    public async Task Handle_ShouldPublishCatalogUpdateEvent()
    {
        // Arrange
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
        await _handler.HandleAsync(paymentEvent);

        // Assert
        _mockMessageBus.Verify(x => x.PublishAsync(It.IsAny<CatalogUpdateEvent>()), Times.Once);
    }

    [Fact]
    public async Task Handle_ShouldPublishNotificationEvent()
    {
        // Arrange
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
        await _handler.HandleAsync(paymentEvent);

        // Assert
        _mockMessageBus.Verify(x => x.PublishAsync(It.IsAny<NotificationEvent>()), Times.Once);
    }

    [Fact]
    public async Task Handle_ShouldLogProcessedEvent()
    {
        // Arrange
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
        await _handler.HandleAsync(paymentEvent);

        // Assert
        _mockLogRepository.Verify(x => x.SaveAsync(It.Is<LogEntry>(log =>
            log.EventName == "PaymentProcessedEvent" &&
            log.Status == "PROCESSED"
        )), Times.Once);
    }
}
