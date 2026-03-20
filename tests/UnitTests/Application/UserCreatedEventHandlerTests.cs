using Moq;
using Xunit;
using Orchestrator.Application;
using Orchestrator.Domain;
using Orchestrator.Domain.Events;

namespace Orchestrator.UnitTests.Application;

public class UserCreatedEventHandlerTests
{
    private readonly Mock<IMessageBus> _mockMessageBus;
    private readonly Mock<ILogRepository> _mockLogRepository;
    private readonly UserCreatedEventHandler _handler;

    public UserCreatedEventHandlerTests()
    {
        _mockMessageBus = new Mock<IMessageBus>();
        _mockLogRepository = new Mock<ILogRepository>();
        _handler = new UserCreatedEventHandler(_mockMessageBus.Object, _mockLogRepository.Object);
    }

    [Fact]
    public async Task Handle_ShouldLogReceivedEvent()
    {
        // Arrange
        var userEvent = new UserCreatedEvent
        {
            UserId = "user123",
            Email = "test@example.com",
            CreatedAt = DateTime.UtcNow
        };

        // Act
        await _handler.HandleAsync(userEvent);

        // Assert
        _mockLogRepository.Verify(x => x.SaveAsync(It.Is<LogEntry>(log =>
            log.EventName == "UserCreatedEvent" &&
            log.Status == "RECEIVED"
        )), Times.Once);
    }

    [Fact]
    public async Task Handle_ShouldPublishNotificationEvent()
    {
        // Arrange
        var userEvent = new UserCreatedEvent
        {
            UserId = "user123",
            Email = "test@example.com",
            CreatedAt = DateTime.UtcNow
        };

        // Act
        await _handler.HandleAsync(userEvent);

        // Assert
        _mockMessageBus.Verify(x => x.PublishAsync(It.IsAny<NotificationEvent>()), Times.Once);
    }

    [Fact]
    public async Task Handle_ShouldLogProcessedEvent()
    {
        // Arrange
        var userEvent = new UserCreatedEvent
        {
            UserId = "user123",
            Email = "test@example.com",
            CreatedAt = DateTime.UtcNow
        };

        // Act
        await _handler.HandleAsync(userEvent);

        // Assert
        _mockLogRepository.Verify(x => x.SaveAsync(It.Is<LogEntry>(log =>
            log.EventName == "UserCreatedEvent" &&
            log.Status == "PROCESSED"
        )), Times.Once);
    }
}
