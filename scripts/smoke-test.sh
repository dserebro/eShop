#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# smoke-test.sh
# Verify all eShop infrastructure services are running and accessible.
# Checks: PostgreSQL (5432), RabbitMQ (5672, 15672), Redis (6379).
# =============================================================================

echo "============================================================"
echo "  eShop Infrastructure Smoke Test"
echo "============================================================"
echo ""

ESHOP_DB_USER="${ESHOP_DB_USER:-eshop}"
ESHOP_DB_PASS="${ESHOP_DB_PASS:-eshoppass}"

PASS=0
FAIL=0

# Helper function for test results
check() {
    local name="$1"
    local result="$2"
    if [ "$result" -eq 0 ]; then
        echo "  [PASS] ${name}"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] ${name}"
        FAIL=$((FAIL + 1))
    fi
}

# ---------------------------------------------------------------------------
# 1. PostgreSQL checks
# ---------------------------------------------------------------------------
echo "--- PostgreSQL ---"

# Check port 5432 is listening
if ss -tlnp | grep -q ":5432 "; then
    check "Port 5432 is listening" 0
else
    check "Port 5432 is listening" 1
fi

# Check PostgreSQL service is active
if sudo systemctl is-active --quiet postgresql; then
    check "PostgreSQL service is active" 0
else
    check "PostgreSQL service is active" 1
fi

# Check databases exist
for DB in catalogdb identitydb orderingdb webhooksdb; do
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB}'" 2>/dev/null | grep -q 1; then
        check "Database '${DB}' exists" 0
    else
        check "Database '${DB}' exists" 1
    fi
done

# Check eshop user can connect
if PGPASSWORD="${ESHOP_DB_PASS}" psql -h 127.0.0.1 -U "${ESHOP_DB_USER}" -d catalogdb -c "SELECT 1;" >/dev/null 2>&1; then
    check "User '${ESHOP_DB_USER}' can connect to catalogdb" 0
else
    check "User '${ESHOP_DB_USER}' can connect to catalogdb" 1
fi

echo ""

# ---------------------------------------------------------------------------
# 2. RabbitMQ checks
# ---------------------------------------------------------------------------
echo "--- RabbitMQ ---"

# Check port 5672 is listening (AMQP)
if ss -tlnp | grep -q ":5672 "; then
    check "Port 5672 (AMQP) is listening" 0
else
    check "Port 5672 (AMQP) is listening" 1
fi

# Check port 15672 is listening (Management UI)
if ss -tlnp | grep -q ":15672 "; then
    check "Port 15672 (Management) is listening" 0
else
    check "Port 15672 (Management) is listening" 1
fi

# Check RabbitMQ service is active
if sudo systemctl is-active --quiet rabbitmq-server; then
    check "RabbitMQ service is active" 0
else
    check "RabbitMQ service is active" 1
fi

# Check vhost exists
if sudo rabbitmqctl list_vhosts --formatter json 2>/dev/null | grep -q '"/eshop"'; then
    check "Vhost '/eshop' exists" 0
else
    check "Vhost '/eshop' exists" 1
fi

# Check user exists
if sudo rabbitmqctl list_users --formatter json 2>/dev/null | grep -q '"eshop"'; then
    check "User 'eshop' exists" 0
else
    check "User 'eshop' exists" 1
fi

echo ""

# ---------------------------------------------------------------------------
# 3. Redis checks
# ---------------------------------------------------------------------------
echo "--- Redis ---"

# Check port 6379 is listening
if ss -tlnp | grep -q ":6379 "; then
    check "Port 6379 is listening" 0
else
    check "Port 6379 is listening" 1
fi

# Check Redis service is active
if sudo systemctl is-active --quiet redis-server; then
    check "Redis service is active" 0
else
    check "Redis service is active" 1
fi

# Check Redis responds to PING
if redis-cli ping 2>/dev/null | grep -q "PONG"; then
    check "Redis responds to PING" 0
else
    check "Redis responds to PING" 1
fi

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
echo "============================================================"
echo "  Results: ${PASS}/${TOTAL} checks passed, ${FAIL} failed"
echo "============================================================"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Some checks failed. Run the provisioning scripts first:"
    echo "  bash scripts/provision-all.sh"
    exit 1
fi

echo ""
echo "All infrastructure services are healthy!"
exit 0
