#!/usr/bin/env python3
"""
Script para publicar eventos de teste no RabbitMQ do Kubernetes
Uso: python3 publish-event.py [user|order|payment]
"""

import pika
import json
import sys

def publish_user_created():
    event = {
        "UserId": "test-user-123",
        "Email": "teste@example.com",
        "CreatedAt": "2026-03-20T17:00:00Z"
    }
    return "user.created", event

def publish_order_placed():
    event = {
        "OrderId": "order-456",
        "UserId": "user-123",
        "TotalAmount": 299.99,
        "PlacedAt": "2026-03-20T17:00:00Z"
    }
    return "order.placed", event

def publish_payment_processed():
    event = {
        "PaymentId": "pay-789",
        "OrderId": "order-456",
        "ProductId": "prod-111",
        "UserId": "user-123",
        "IsSuccessful": True,
        "ProcessedAt": "2026-03-20T17:05:00Z"
    }
    return "payment.processed", event

def main():
    event_type = sys.argv[1] if len(sys.argv) > 1 else "user"
    
    # Mapear tipo de evento
    events_map = {
        "user": publish_user_created,
        "order": publish_order_placed,
        "payment": publish_payment_processed
    }
    
    if event_type not in events_map:
        print(f"❌ Tipo de evento inválido: {event_type}")
        print(f"Uso: {sys.argv[0]} [user|order|payment]")
        sys.exit(1)
    
    queue_name, event = events_map[event_type]()
    
    # Conectar ao RabbitMQ (via port-forward localhost:5672)
    print(f"📡 Conectando ao RabbitMQ em localhost:5672...")
    credentials = pika.PlainCredentials('admin', 'admin123')
    connection = pika.BlockingConnection(
        pika.ConnectionParameters('localhost', 5672, '/', credentials)
    )
    channel = connection.channel()
    
    # Declarar fila
    channel.queue_declare(queue=queue_name, durable=True)
    
    # Publicar evento
    channel.basic_publish(
        exchange='',
        routing_key=queue_name,
        body=json.dumps(event),
        properties=pika.BasicProperties(
            content_type='application/json',
            delivery_mode=2
        )
    )
    
    print(f"✅ Evento publicado na fila: {queue_name}")
    print(f"📦 Payload: {json.dumps(event, indent=2)}")
    
    connection.close()

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"❌ Erro: {e}")
        print("\n💡 Dica: Execute antes:")
        print("   kubectl port-forward svc/rabbitmq 5672:5672")
        sys.exit(1)
