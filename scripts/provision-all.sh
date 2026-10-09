#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# provision-all.sh
# Master provisioning script: invokes all individual provisioning scripts,
# verifies health, and prints connection strings.
# Idempotent: safe to re-run.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "  eShop Infrastructure Provisioning - Ubuntu 24.04"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# 1. Run individual provisioning scripts
# ---------------------------------------------------------------------------
echo "--- Step 1/3: Provisioning PostgreSQL ---"
bash "${SCRIPT_DIR}/provision-postgres.sh"
echo ""

echo "--- Step 2/3: Provisioning RabbitMQ ---"
bash "${SCRIPT_DIR}/provision-rabbitmq.sh"
echo ""

echo "--- Step 3/3: Provisioning Redis ---"
bash "${SCRIPT_DIR}/provision-redis.sh"
echo ""

# ---------------------------------------------------------------------------
# 2. Health verification
# ---------------------------------------------------------------------------
echo "============================================================"
echo "  Health Verification"
echo "============================================================"

HEALTHY=true

# PostgreSQL
echo -n "PostgreSQL (port 5432): "
if sudo -u postgres psql -c "SELECT 1;" >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    HEALTHY=false
fi

# RabbitMQ
echo -n "RabbitMQ (port 5672):  "
if sudo rabbitmqctl status >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    HEALTHY=false
fi

echo -n "RabbitMQ Management (port 15672): "
if sudo rabbitmq-plugins list -e 2>/dev/null | grep -q rabbitmq_management; then
    echo "OK"
else
    echo "FAILED"
    HEALTHY=false
fi

# Redis
echo -n "Redis (port 6379):     "
if redis-cli ping 2>/dev/null | grep -q "PONG"; then
    echo "OK"
else
    echo "FAILED"
    HEALTHY=false
fi

echo ""

if [ "$HEALTHY" = false ]; then
    echo "ERROR: One or more services failed health checks."
    exit 1
fi

echo "All services are healthy."
echo ""

# ---------------------------------------------------------------------------
# 3. Print connection strings
# ---------------------------------------------------------------------------
echo "============================================================"
echo "  Connection Strings"
echo "============================================================"
echo ""
echo "Export these environment variables for the eShop application:"
echo ""
echo "ConnectionStrings__catalogdb=Host=localhost;Database=catalogdb;Username=eshop;Password=eshoppass"
echo "ConnectionStrings__orderingdb=Host=localhost;Database=orderingdb;Username=eshop;Password=eshoppass"
echo "ConnectionStrings__identitydb=Host=localhost;Database=identitydb;Username=eshop;Password=eshoppass"
echo "ConnectionStrings__webhooksdb=Host=localhost;Database=webhooksdb;Username=eshop;Password=eshoppass"
echo "ConnectionStrings__EventBus=amqp://eshop:eshoppass@localhost:5672"
echo "ConnectionStrings__redis=localhost:6379"
echo ""
echo "============================================================"
echo "  Provisioning Complete"
echo "============================================================"
