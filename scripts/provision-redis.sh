#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# provision-redis.sh
# Install Redis 7.2, configure for localhost, verify connectivity.
# Idempotent: safe to re-run.
# =============================================================================

echo "=== Provisioning Redis 7.2 ==="

# ---------------------------------------------------------------------------
# 1. Install Redis
# ---------------------------------------------------------------------------
if ! dpkg -s redis-server &>/dev/null; then
    echo "Installing Redis..."

    # Add the official Redis APT repository if not already present
    if [ ! -f /etc/apt/sources.list.d/redis.list ]; then
        echo "Adding Redis APT repository..."
        sudo apt-get update -qq
        sudo apt-get install -y -qq curl gnupg lsb-release >/dev/null
        curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg 2>/dev/null || true
        echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list >/dev/null
        sudo apt-get update -qq
    fi

    sudo apt-get install -y -qq redis-server >/dev/null
    echo "Redis installed."
else
    echo "Redis is already installed."
fi

# ---------------------------------------------------------------------------
# 2. Configure Redis for localhost binding
# ---------------------------------------------------------------------------
REDIS_CONF="/etc/redis/redis.conf"

if [ -f "$REDIS_CONF" ]; then
    # Ensure bind is set to localhost only
    if sudo grep -q "^bind 127.0.0.1" "$REDIS_CONF"; then
        echo "Redis already configured to bind to localhost."
    else
        echo "Configuring Redis to bind to localhost..."
        # Comment out any existing bind directives and add localhost binding
        sudo sed -i 's/^bind .*/# &/' "$REDIS_CONF"
        echo "bind 127.0.0.1 ::1" | sudo tee -a "$REDIS_CONF" >/dev/null
        echo "Redis bind address configured."
    fi
else
    echo "WARNING: Redis config not found at ${REDIS_CONF}. Skipping bind configuration."
fi

# ---------------------------------------------------------------------------
# 3. Ensure Redis service is running
# ---------------------------------------------------------------------------
if ! sudo systemctl is-active --quiet redis-server; then
    echo "Starting Redis service..."
    sudo systemctl start redis-server
    sudo systemctl enable redis-server
else
    # Restart to pick up any config changes
    echo "Restarting Redis to apply configuration..."
    sudo systemctl restart redis-server
fi
echo "Redis service is running."

# ---------------------------------------------------------------------------
# 4. Verify Redis responds to PING
# ---------------------------------------------------------------------------
echo "Verifying Redis connectivity..."
RETRIES=5
for i in $(seq 1 $RETRIES); do
    if redis-cli ping 2>/dev/null | grep -q "PONG"; then
        echo "Redis is responding to PING - PONG received."
        break
    fi
    if [ "$i" -eq "$RETRIES" ]; then
        echo "ERROR: Redis is not responding to PING after ${RETRIES} attempts."
        exit 1
    fi
    echo "Waiting for Redis to be ready (attempt ${i}/${RETRIES})..."
    sleep 1
done

echo "=== Redis 7.2 provisioning complete ==="
