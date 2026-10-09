#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# provision-rabbitmq.sh
# Install RabbitMQ 3.13, enable management plugin, create vhost and user.
# Idempotent: safe to re-run.
# =============================================================================

RABBIT_USER="eshop"
RABBIT_PASS="eshoppass"
RABBIT_VHOST="/eshop"

echo "=== Provisioning RabbitMQ 3.13 ==="

# ---------------------------------------------------------------------------
# 1. Install Erlang and RabbitMQ
# ---------------------------------------------------------------------------
if ! dpkg -s rabbitmq-server &>/dev/null; then
    echo "Installing RabbitMQ..."

    # Install prerequisites
    sudo apt-get update -qq
    sudo apt-get install -y -qq curl gnupg apt-transport-https >/dev/null

    # Add Erlang repository (Cloudsmith / RabbitMQ team)
    if [ ! -f /etc/apt/sources.list.d/rabbitmq.list ]; then
        echo "Adding RabbitMQ and Erlang APT repositories..."

        # Add signing keys
        curl -1sLf "https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA" | sudo gpg --dearmor -o /usr/share/keyrings/com.rabbitmq.team.gpg 2>/dev/null || true
        curl -1sLf "https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-erlang.E495BB49CC4BBE5B.key" | sudo gpg --dearmor -o /usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg 2>/dev/null || true
        curl -1sLf "https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key" | sudo gpg --dearmor -o /usr/share/keyrings/rabbitmq.9F4587F226208342.gpg 2>/dev/null || true

        CODENAME=$(lsb_release -cs)

        sudo tee /etc/apt/sources.list.d/rabbitmq.list >/dev/null <<EOF
## Erlang from RabbitMQ team
deb [signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-erlang/deb/ubuntu ${CODENAME} main
deb-src [signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-erlang/deb/ubuntu ${CODENAME} main

## RabbitMQ server
deb [signed-by=/usr/share/keyrings/rabbitmq.9F4587F226208342.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-server/deb/ubuntu ${CODENAME} main
deb-src [signed-by=/usr/share/keyrings/rabbitmq.9F4587F226208342.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-server/deb/ubuntu ${CODENAME} main
EOF
        sudo apt-get update -qq
    fi

    # Install Erlang first, then RabbitMQ
    sudo apt-get install -y -qq erlang-base erlang-asn1 erlang-crypto erlang-eldap \
        erlang-ftp erlang-inets erlang-mnesia erlang-os-mon erlang-parsetools \
        erlang-public-key erlang-runtime-tools erlang-snmp erlang-ssl \
        erlang-syntax-tools erlang-tftp erlang-tools erlang-xmerl >/dev/null

    sudo apt-get install -y -qq rabbitmq-server >/dev/null
    echo "RabbitMQ installed."
else
    echo "RabbitMQ is already installed."
fi

# ---------------------------------------------------------------------------
# 2. Ensure RabbitMQ service is running
# ---------------------------------------------------------------------------
if ! sudo systemctl is-active --quiet rabbitmq-server; then
    echo "Starting RabbitMQ service..."
    sudo systemctl start rabbitmq-server
    sudo systemctl enable rabbitmq-server
fi
echo "RabbitMQ service is running."

# ---------------------------------------------------------------------------
# 3. Enable management plugin
# ---------------------------------------------------------------------------
if sudo rabbitmq-plugins list -e | grep -q rabbitmq_management; then
    echo "RabbitMQ management plugin is already enabled."
else
    echo "Enabling RabbitMQ management plugin..."
    sudo rabbitmq-plugins enable rabbitmq_management
    echo "Management plugin enabled."
fi

# ---------------------------------------------------------------------------
# 4. Create vhost
# ---------------------------------------------------------------------------
if sudo rabbitmqctl list_vhosts --formatter json 2>/dev/null | grep -q "\"name\":\"${RABBIT_VHOST}\""; then
    echo "Vhost '${RABBIT_VHOST}' already exists."
else
    echo "Creating vhost '${RABBIT_VHOST}'..."
    sudo rabbitmqctl add_vhost "${RABBIT_VHOST}"
    echo "Vhost '${RABBIT_VHOST}' created."
fi

# ---------------------------------------------------------------------------
# 5. Create user and set permissions
# ---------------------------------------------------------------------------
if sudo rabbitmqctl list_users --formatter json 2>/dev/null | grep -q "\"user\":\"${RABBIT_USER}\""; then
    echo "RabbitMQ user '${RABBIT_USER}' already exists."
    # Update password in case it changed
    sudo rabbitmqctl change_password "${RABBIT_USER}" "${RABBIT_PASS}" >/dev/null
else
    echo "Creating RabbitMQ user '${RABBIT_USER}'..."
    sudo rabbitmqctl add_user "${RABBIT_USER}" "${RABBIT_PASS}"
    echo "User '${RABBIT_USER}' created."
fi

# Set permissions on the vhost (idempotent)
echo "Setting permissions for '${RABBIT_USER}' on '${RABBIT_VHOST}'..."
sudo rabbitmqctl set_permissions -p "${RABBIT_VHOST}" "${RABBIT_USER}" ".*" ".*" ".*"

# Also set permissions on default vhost for compatibility
sudo rabbitmqctl set_permissions -p "/" "${RABBIT_USER}" ".*" ".*" ".*" 2>/dev/null || true

# Set user tags (management access)
sudo rabbitmqctl set_user_tags "${RABBIT_USER}" administrator 2>/dev/null || true

# ---------------------------------------------------------------------------
# 6. Verify service is running
# ---------------------------------------------------------------------------
echo "Verifying RabbitMQ..."
if sudo rabbitmqctl status >/dev/null 2>&1; then
    echo "RabbitMQ is healthy and responding."
else
    echo "ERROR: RabbitMQ is not responding."
    exit 1
fi

echo "=== RabbitMQ 3.13 provisioning complete ==="
