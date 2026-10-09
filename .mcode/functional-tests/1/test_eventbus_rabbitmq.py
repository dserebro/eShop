"""
Functional tests for EventBusRabbitMQ migration (Milestone 1).

Verifies that the migrated EventBusRabbitMQ library correctly connects to RabbitMQ
using direct RabbitMQ.Client instead of Aspire.RabbitMQ.Client. Tests validate
observable side effects: exchange creation, queue registration, event bindings,
and end-to-end message processing.

The RabbitMQ management API (port 15672) is used to observe the application's
runtime behavior on the message broker.
"""
import json
import os
import time
import uuid

import pytest
import requests

RABBITMQ_MGMT_URL = "http://localhost:15672"
RABBITMQ_AUTH = (os.environ.get("ESHOP_RABBIT_USER", "eshop"), os.environ.get("ESHOP_RABBIT_PASS", "eshoppass"))
EXCHANGE_NAME = "eshop_event_bus"
VHOST_ENCODED = "%2f"


@pytest.fixture(autouse=True)
def rabbitmq_management_reachable():
    """Confirm the RabbitMQ management API is reachable before running tests."""
    resp = requests.get(
        f"{RABBITMQ_MGMT_URL}/api/overview",
        auth=RABBITMQ_AUTH,
        timeout=5,
    )
    assert resp.status_code == 200, (
        f"RabbitMQ management API not reachable: {resp.status_code}"
    )


class TestEshopEventBusExchange:
    """Verify the eshop_event_bus exchange is created by the migrated EventBusRabbitMQ."""

    def test_exchange_exists(self):
        """The eshop_event_bus exchange must exist, proving EventBusRabbitMQ connected."""
        resp = requests.get(
            f"{RABBITMQ_MGMT_URL}/api/exchanges/{VHOST_ENCODED}/{EXCHANGE_NAME}",
            auth=RABBITMQ_AUTH,
            timeout=10,
        )
        assert resp.status_code == 200, (
            f"Exchange {EXCHANGE_NAME} not found: {resp.status_code}"
        )
        data = resp.json()
        assert data["name"] == EXCHANGE_NAME
        assert data["type"] == "direct", (
            f"Exchange type should be 'direct', got '{data['type']}'"
        )

    def test_exchange_not_auto_delete(self):
        """The exchange should not be auto-delete (per RabbitMQEventBus.StartAsync)."""
        resp = requests.get(
            f"{RABBITMQ_MGMT_URL}/api/exchanges/{VHOST_ENCODED}/{EXCHANGE_NAME}",
            auth=RABBITMQ_AUTH,
            timeout=10,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["auto_delete"] is False


class TestPaymentProcessorQueue:
    """Verify PaymentProcessor created its RabbitMQ queue via the migrated EventBusRabbitMQ."""

    def test_queue_exists(self):
        """PaymentProcessor queue must exist, proving the service connected to RabbitMQ."""
        resp = requests.get(
            f"{RABBITMQ_MGMT_URL}/api/queues/{VHOST_ENCODED}/PaymentProcessor",
            auth=RABBITMQ_AUTH,
            timeout=10,
        )
        assert resp.status_code == 200, (
            f"PaymentProcessor queue not found: {resp.status_code}"
        )
        data = resp.json()
        assert data["name"] == "PaymentProcessor"

    def test_queue_is_durable(self):
        """PaymentProcessor queue should be durable (per RabbitMQEventBus.StartAsync)."""
        resp = requests.get(
            f"{RABBITMQ_MGMT_URL}/api/queues/{VHOST_ENCODED}/PaymentProcessor",
            auth=RABBITMQ_AUTH,
            timeout=10,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["durable"] is True

    def test_event_binding_exists(self):
        """PaymentProcessor should have binding for OrderStatusChangedToStockConfirmedIntegrationEvent."""
        resp = requests.get(
            f"{RABBITMQ_MGMT_URL}/api/queues/{VHOST_ENCODED}/PaymentProcessor/bindings",
            auth=RABBITMQ_AUTH,
            timeout=10,
        )
        assert resp.status_code == 200
        bindings = resp.json()
        event_bindings = [
            b for b in bindings
            if b.get("source") == EXCHANGE_NAME
        ]
        routing_keys = [b["routing_key"] for b in event_bindings]
        assert "OrderStatusChangedToStockConfirmedIntegrationEvent" in routing_keys, (
            f"Expected binding for OrderStatusChangedToStockConfirmedIntegrationEvent, "
            f"found routing keys: {routing_keys}"
        )


class TestOrderProcessorQueue:
    """Verify OrderProcessor created its RabbitMQ queue via the migrated EventBusRabbitMQ."""

    def test_queue_exists(self):
        """OrderProcessor queue must exist, proving the service connected to RabbitMQ."""
        resp = requests.get(
            f"{RABBITMQ_MGMT_URL}/api/queues/{VHOST_ENCODED}/OrderProcessor",
            auth=RABBITMQ_AUTH,
            timeout=10,
        )
        assert resp.status_code == 200, (
            f"OrderProcessor queue not found: {resp.status_code}"
        )
        data = resp.json()
        assert data["name"] == "OrderProcessor"

    def test_queue_is_durable(self):
        """OrderProcessor queue should be durable (per RabbitMQEventBus.StartAsync)."""
        resp = requests.get(
            f"{RABBITMQ_MGMT_URL}/api/queues/{VHOST_ENCODED}/OrderProcessor",
            auth=RABBITMQ_AUTH,
            timeout=10,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["durable"] is True

    def test_no_subscription_bindings(self):
        """OrderProcessor only publishes events (no AddSubscription calls), so no exchange bindings."""
        resp = requests.get(
            f"{RABBITMQ_MGMT_URL}/api/queues/{VHOST_ENCODED}/OrderProcessor/bindings",
            auth=RABBITMQ_AUTH,
            timeout=10,
        )
        assert resp.status_code == 200
        bindings = resp.json()
        exchange_bindings = [
            b for b in bindings
            if b.get("source") == EXCHANGE_NAME
        ]
        assert len(exchange_bindings) == 0, (
            f"OrderProcessor should have no exchange bindings (publish-only), "
            f"found: {exchange_bindings}"
        )


class TestPaymentProcessorMessageProcessing:
    """End-to-end test: publish an event and verify PaymentProcessor processes it."""

    RESPONSE_QUEUE = f"ftrun_{uuid.uuid4().hex[:8]}_response"

    @pytest.fixture(autouse=True)
    def setup_response_queue(self):
        """Create a temporary queue to capture the response event, clean up after."""
        # Create a temporary queue
        resp = requests.put(
            f"{RABBITMQ_MGMT_URL}/api/queues/{VHOST_ENCODED}/{self.RESPONSE_QUEUE}",
            auth=RABBITMQ_AUTH,
            json={"auto_delete": True, "durable": False},
            timeout=10,
        )
        assert resp.status_code in (201, 204), (
            f"Failed to create response queue: {resp.status_code} {resp.text}"
        )
        # Bind for both possible response events
        for event_name in [
            "OrderPaymentSucceededIntegrationEvent",
            "OrderPaymentFailedIntegrationEvent",
        ]:
            resp = requests.post(
                f"{RABBITMQ_MGMT_URL}/api/bindings/{VHOST_ENCODED}/e/{EXCHANGE_NAME}/q/{self.RESPONSE_QUEUE}",
                auth=RABBITMQ_AUTH,
                json={"routing_key": event_name},
                timeout=10,
            )
            assert resp.status_code in (201, 204), (
                f"Failed to bind response queue for {event_name}: {resp.status_code}"
            )
        yield
        # Cleanup: delete the temporary queue
        requests.delete(
            f"{RABBITMQ_MGMT_URL}/api/queues/{VHOST_ENCODED}/{self.RESPONSE_QUEUE}",
            auth=RABBITMQ_AUTH,
            timeout=10,
        )

    def test_payment_processor_handles_stock_confirmed_event(self):
        """Publish OrderStatusChangedToStockConfirmedIntegrationEvent,
        expect PaymentProcessor to respond with OrderPaymentSucceededIntegrationEvent."""
        # Build the integration event payload matching the .NET record format
        event_payload = json.dumps({
            "OrderId": 99999,
            "Id": str(uuid.uuid4()),
            "CreationDate": "2026-10-09T12:00:00Z",
        })

        # Publish the event to the exchange
        publish_resp = requests.post(
            f"{RABBITMQ_MGMT_URL}/api/exchanges/{VHOST_ENCODED}/{EXCHANGE_NAME}/publish",
            auth=RABBITMQ_AUTH,
            json={
                "properties": {
                    "delivery_mode": 2,
                    "content_type": "application/json",
                },
                "routing_key": "OrderStatusChangedToStockConfirmedIntegrationEvent",
                "payload": event_payload,
                "payload_encoding": "string",
            },
            timeout=10,
        )
        assert publish_resp.status_code == 200, (
            f"Failed to publish event: {publish_resp.status_code} {publish_resp.text}"
        )
        publish_data = publish_resp.json()
        assert publish_data.get("routed") is True, (
            "Event was not routed to any queue"
        )

        # Wait for PaymentProcessor to process the event and publish a response
        response_event = None
        for attempt in range(15):
            time.sleep(1)
            get_resp = requests.post(
                f"{RABBITMQ_MGMT_URL}/api/queues/{VHOST_ENCODED}/{self.RESPONSE_QUEUE}/get",
                auth=RABBITMQ_AUTH,
                json={
                    "count": 1,
                    "ackmode": "ack_requeue_false",
                    "encoding": "auto",
                },
                timeout=10,
            )
            if get_resp.status_code == 200:
                messages = get_resp.json()
                if messages and len(messages) > 0:
                    response_event = messages[0]
                    break

        assert response_event is not None, (
            "PaymentProcessor did not publish a response event within 15 seconds"
        )
        routing_key = response_event.get("routing_key", "")
        assert routing_key == "OrderPaymentSucceededIntegrationEvent", (
            f"Expected OrderPaymentSucceededIntegrationEvent, got {routing_key}"
        )

        # Verify the response payload contains the correct OrderId
        # Note: PaymentProcessor's OrderPaymentSucceededIntegrationEvent uses
        # [JsonPropertyName("OrderNumber")] on the OrderId property
        payload = json.loads(response_event["payload"])
        assert payload.get("OrderNumber") == 99999, (
            f"Response OrderNumber should be 99999, got {payload.get('OrderNumber')}"
        )
