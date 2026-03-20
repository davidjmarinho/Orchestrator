# Copilot Instructions — Orchestrator (.NET 8 Worker + RabbitMQ + MongoDB + Kubernetes)

You are a senior software architect.

Your task is to generate a **.NET 8 Orchestrator Worker Service** responsible for:

- Coordinating microservices communication
    
- Managing event flows using RabbitMQ
    
- Persisting logs in MongoDB
    
- Acting as orchestration layer for Kubernetes-based microservices
    

---

# Architecture Requirements

The system must follow:

- Clean Architecture
    
- Domain-Driven Design (DDD)
    
- Event-driven architecture
    

---

# Microservices Context

The orchestrator integrates with:

- UsersAPI
    
- CatalogAPI
    
- PaymentsAPI
    
- NotificationsAPI
    

---

# High-Level Responsibilities

The Orchestrator must:

1. Consume events from RabbitMQ
    
2. Orchestrate flows between services
    
3. Persist all events and processing logs in MongoDB
    
4. Handle failures and log errors
    

---

# Event Flows

## User Flow

UsersAPI → UserCreatedEvent → Orchestrator → NotificationsAPI

## Purchase Flow

CatalogAPI → OrderPlacedEvent → Orchestrator → PaymentsAPI  
PaymentsAPI → PaymentProcessedEvent → Orchestrator → CatalogAPI + NotificationsAPI

---

# Project Structure (Clean Architecture)

```text
src/
 ├── Orchestrator.Domain
 ├── Orchestrator.Application
 ├── Orchestrator.Infrastructure
 └── Orchestrator.Worker
```

---

# Domain Layer

Contains:

- Domain Events:
    
    - UserCreatedEvent
        
    - OrderPlacedEvent
        
    - PaymentProcessedEvent
        
- Log Entity:
    

```csharp
class LogEntry
{
    string Id;
    string EventName;
    string Payload;
    string Status;
    string Error;
    DateTime CreatedAt;
}
```

- Interfaces:
    

```csharp
ILogRepository
IMessageBus
IEventHandler<T>
```

---

# Application Layer

Contains:

- Event Handlers:
    
    - UserCreatedEventHandler
        
    - OrderPlacedEventHandler
        
    - PaymentProcessedEventHandler
        

Responsibilities:

- Orchestrate flows
    
- Call IMessageBus
    
- Persist logs via ILogRepository
    

Each handler must:

1. Log event received
    
2. Execute orchestration logic
    
3. Log success or failure
    

---

# Infrastructure Layer

## RabbitMQ

Implement:

- RabbitMqConnectionFactory
    
- RabbitMqPublisher
    
- RabbitMqConsumer
    
- RabbitMqHostedService
    

---

## MongoDB Integration

Use official MongoDB driver.

Implement:

- MongoDbContext
    
- LogRepository
    

Example:

```csharp
public class LogRepository : ILogRepository
{
    private readonly IMongoCollection<LogEntry> _collection;

    public Task SaveAsync(LogEntry log)
    {
        return _collection.InsertOneAsync(log);
    }
}
```

---

# Worker Layer

- Configure Dependency Injection
    
- Register RabbitMQ consumers
    
- Register MongoDB
    
- Start Hosted Services
    

---

# Environment Variables

```text
RABBITMQ_HOST=rabbitmq
RABBITMQ_PORT=5672
RABBITMQ_USER=admin
RABBITMQ_PASS=admin123

MONGO_HOST=mongodb
MONGO_PORT=27017
MONGO_DB=orchestrator
```

---

# Dockerfile

Multi-stage build:

- restore
    
- publish
    
- runtime
    

Expose:

```text
80
```

---

# Docker Compose

Create `docker-compose.yml` including:

- rabbitmq
    
- mongodb
    
- orchestrator
    
- users-api
    
- catalog-api
    
- payments-api
    
- notifications-api
    

MongoDB:

- port 27017
    
- default configuration
    

RabbitMQ:

- image rabbitmq:3-management
    
- ports 5672, 15672
    

All services must share network.

---

# Kubernetes

Create `/k8s` folder with:

- orchestrator-deployment.yaml
    
- orchestrator-service.yaml
    
- orchestrator-configmap.yaml
    
- orchestrator-secret.yaml
    
- mongodb-deployment.yaml
    
- mongodb-service.yaml
    

---

# MongoDB Deployment

Must include:

- 1 replica
    
- container port 27017
    
- ClusterIP service
    
- DNS name:
    

```text
mongodb
```

---

# ConfigMap

Store:

- queue names
    
- mongo host
    

---

# Secrets

Store:

- RabbitMQ credentials
    
- Mongo credentials (if used)
    

---

# Logging Strategy

Every event must generate logs:

- RECEIVED
    
- PROCESSED
    
- FAILED
    

Persist in MongoDB.

---

# Expected Result

The system must:

- Run orchestrator as .NET Worker
    
- Consume and publish RabbitMQ events
    
- Persist logs in MongoDB
    
- Run via Docker Compose
    
- Deploy to Kubernetes
    
- Follow Clean Architecture and DDD