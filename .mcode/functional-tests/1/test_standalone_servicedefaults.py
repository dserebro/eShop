"""Container-free functional checks for ServiceDefaults (health endpoints, OpenTelemetry, resilience).

Prerequisite: Basket.API and WebApp are running standalone, started by
$MCODE_DIR/functional_testing/start_standalone.ps1 (WebApp additionally needs CallBackUrl=http://localhost:5045).
Redis and RabbitMQ are intentionally NOT available, so /alive (liveness) must be 200 while /health (readiness,
includes backing-service checks) must be 503.
"""
import os

import pytest
import requests

BASKET = os.environ.get("BASKET_API_URL", "http://localhost:5221")
WEBAPP = os.environ.get("WEBAPP_URL", "http://localhost:5045")


@pytest.fixture(autouse=True, scope="session")
def services_up():
    for base in (BASKET, WEBAPP):
        try:
            requests.get(f"{base}/alive", timeout=10)
        except requests.RequestException as exc:
            pytest.skip(f"{base} not reachable: {exc}")


class TestAlive:
    @pytest.mark.parametrize("base", [BASKET, WEBAPP])
    def test_alive_returns_200_healthy(self, base):
        r = requests.get(f"{base}/alive", timeout=15)
        assert r.status_code == 200
        assert r.text == "Healthy"


class TestHealth:
    @pytest.mark.parametrize("base", [BASKET, WEBAPP])
    def test_health_is_503_without_backing_services(self, base):
        # Redis/RabbitMQ health checks fail and time out (~55s) when the containers are absent.
        r = requests.get(f"{base}/health", timeout=120)
        assert r.status_code == 503
        assert r.text == "Unhealthy"


class TestWebApp:
    def test_unknown_route_returns_404(self):
        r = requests.get(f"{WEBAPP}/nonexistent", timeout=15)
        assert r.status_code == 404

    def test_home_renders_shell(self):
        r = requests.get(f"{WEBAPP}/", timeout=60)
        assert r.status_code == 200
        assert "<html" in r.text.lower()
