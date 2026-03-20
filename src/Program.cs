using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Orchestrator.Application;
using Orchestrator.Domain.Events;
using Orchestrator.Domain;
using Orchestrator.Infrastructure;


var builder = Host.CreateApplicationBuilder(args);

// MongoDB Configuration
var mongoHost = Environment.GetEnvironmentVariable("MONGO_HOST") ?? "localhost";
var mongoPort = Environment.GetEnvironmentVariable("MONGO_PORT") ?? "27017";
var mongoDb = Environment.GetEnvironmentVariable("MONGO_DB") ?? "orchestrator";
var mongoUser = Environment.GetEnvironmentVariable("MONGO_USER");
var mongoPass = Environment.GetEnvironmentVariable("MONGO_PASS");

var mongoConnectionString = !string.IsNullOrEmpty(mongoUser) && !string.IsNullOrEmpty(mongoPass)
    ? $"mongodb://{Uri.EscapeDataString(mongoUser)}:{Uri.EscapeDataString(mongoPass)}@{mongoHost}:{mongoPort}"
    : $"mongodb://{mongoHost}:{mongoPort}";

builder.Services.AddSingleton(new MongoDbContext(mongoConnectionString, mongoDb));
builder.Services.AddScoped<ILogRepository, LogRepository>();

// RabbitMQ
builder.Services.AddSingleton<RabbitMqConnectionFactory>();
builder.Services.AddSingleton<IMessageBus, RabbitMqPublisher>();

// Event Handlers
builder.Services.AddScoped<IEventHandler<UserCreatedEvent>, UserCreatedEventHandler>();
builder.Services.AddScoped<IEventHandler<OrderPlacedEvent>, OrderPlacedEventHandler>();
builder.Services.AddScoped<IEventHandler<PaymentProcessedEvent>, PaymentProcessedEventHandler>();

// Hosted Services
builder.Services.AddHostedService<RabbitMqConsumer>();

var app = builder.Build();

app.Run();