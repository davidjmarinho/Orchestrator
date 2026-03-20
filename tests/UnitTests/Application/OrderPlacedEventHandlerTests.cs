using Moq;
using Xunit;
using Orchestrator.Application;
using Orchestrator.Domain;
using Orchestrator.Domain.Events;

namespace Orchestrator.UnitTests.Application;

public class OrderPlacedEventHandlerTests
{
    private readonly Mock<IMessageBus> _mockMessageBus;
    private readonly Mock<ILogRepository> _mockLogRepository;
    private readonly OrderPlacedEventHandler _handler;

    public OrderPlacedEventHandlerTests()
    {
        _mockMessageBus = new Mock<IMessageBus>();
        _mockLogRepository = new Mock<ILogRepository>();
        _handler = new OrderPlacedEventHandler(_mockMessageBus.Object, _mockLogRepository.Object);
    }

    [Fact]
    public async Task Handle_ShouldLogReceivedEvent()
    {
        // Arrange
        var orderEvent = new OrderPlacedEvent
        {
            OrderId = "order123",
            UserId = "user123",
            TotalAmount = 100.00m,
            PlacedAt = DateTime.UtcNow
        };

        // Act
        await _handler.HandleAsync(orderEvent);

        // Assert
        _mockLogRepository.Verify(x => x.SaveAsync(It.Is<LogEntry>(log =>
            log.EventName == "OrderPlacedEvent" &&
            log.Status == "RECEIVED"
        )), Times.Once);
    }

    [Fact]
    public async Task Handle_ShouldPublishPaymentRequestEvent()
    {
        // Arrange
        var orderEvent = new OrderPlacedEvent
        {
            OrderId = "order123",
            UserId = "user123",
            TotalAmount = 100.00m,
            PlacedAt = DateTime.UtcNow
        };

        // Act
        await _handler.HandleAsync(orderEvent);

        // Assert
        _mockMessageBus.Verify(x => x.PublishAsync(It.IsAny<PaymentRequestEvent>()), Times.Once);
    }

    [Fact]
    public async Task Handle_ShouldLogProcessedEvent()
    {
        // Arrange
        var orderEvent = new OrderPlacedEvent
        {
            OrderId = "order123",
            UserId = "user123",
            TotalAmount = 100.00m,
            PlacedAt = DateTime.UtcNow
        };

        // Act
        await _handler.HandleAsync(orderEvent);

        // Assert
        _mockLogRepository.Verify(x => x.SaveAsync(It.Is<LogEntry>(log =>
            log.EventName == "OrderPlacedEvent" &&
            log.Status == "PROCESSED"
        )), Times.Once);
    }
}
