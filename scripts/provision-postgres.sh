#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# provision-postgres.sh
# Install PostgreSQL 16 with pgvector extension, create databases and app user.
# Idempotent: safe to re-run.
# =============================================================================

PGUSER="${ESHOP_DB_USER:-eshop}"
PGPASS="${ESHOP_DB_PASS:-eshoppass}"
DATABASES=("catalogdb" "identitydb" "orderingdb" "webhooksdb")

echo "=== Provisioning PostgreSQL 16 ==="

# ---------------------------------------------------------------------------
# 1. Install PostgreSQL 16 and pgvector extension
# ---------------------------------------------------------------------------
if ! dpkg -s postgresql-16 &>/dev/null; then
    echo "Installing PostgreSQL 16..."
    # Add the official PostgreSQL APT repository if not already present
    if [ ! -f /etc/apt/sources.list.d/pgdg.list ]; then
        echo "Adding PostgreSQL APT repository..."
        sudo apt-get update -qq
        sudo apt-get install -y -qq curl ca-certificates gnupg >/dev/null
        curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg 2>/dev/null || true
        echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list >/dev/null
        sudo apt-get update -qq
    fi
    sudo apt-get install -y -qq postgresql-16 >/dev/null
    echo "PostgreSQL 16 installed."
else
    echo "PostgreSQL 16 is already installed."
fi

if ! dpkg -s postgresql-16-pgvector &>/dev/null; then
    echo "Installing pgvector extension..."
    sudo apt-get install -y -qq postgresql-16-pgvector >/dev/null
    echo "pgvector extension installed."
else
    echo "pgvector extension is already installed."
fi

# ---------------------------------------------------------------------------
# 2. Ensure PostgreSQL service is running
# ---------------------------------------------------------------------------
if ! sudo systemctl is-active --quiet postgresql; then
    echo "Starting PostgreSQL service..."
    sudo systemctl start postgresql
    sudo systemctl enable postgresql
fi
echo "PostgreSQL service is running."

# ---------------------------------------------------------------------------
# 3. Configure pg_hba.conf for local password-based connections
# ---------------------------------------------------------------------------
PG_HBA="/etc/postgresql/16/main/pg_hba.conf"

if [ -f "$PG_HBA" ]; then
    # Ensure local connections use scram-sha-256 (password) authentication for the eshop user
    if ! sudo grep -q "^local\s\+all\s\+${PGUSER}\s\+scram-sha-256" "$PG_HBA" 2>/dev/null; then
        echo "Configuring pg_hba.conf for password-based local connections..."
        # Insert eshop user rule before the default local rules
        sudo sed -i "/^# \"local\" is for Unix domain socket connections only/a local   all             ${PGUSER}                                scram-sha-256" "$PG_HBA"
        sudo systemctl reload postgresql
        echo "pg_hba.conf updated and PostgreSQL reloaded."
    else
        echo "pg_hba.conf already configured for ${PGUSER}."
    fi

    # Also ensure host connections (localhost TCP) use scram-sha-256
    if ! sudo grep -q "^host\s\+all\s\+${PGUSER}\s\+127.0.0.1/32\s\+scram-sha-256" "$PG_HBA" 2>/dev/null; then
        echo "Adding TCP/IP localhost rule for ${PGUSER}..."
        sudo sed -i "/^# IPv4 local connections:/a host    all             ${PGUSER}        127.0.0.1/32            scram-sha-256" "$PG_HBA"
        sudo systemctl reload postgresql
        echo "TCP/IP rule added and PostgreSQL reloaded."
    else
        echo "TCP/IP localhost rule for ${PGUSER} already exists."
    fi
else
    echo "WARNING: pg_hba.conf not found at ${PG_HBA}. Skipping configuration."
fi

# ---------------------------------------------------------------------------
# 4. Create application user
# ---------------------------------------------------------------------------
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${PGUSER}'" | grep -q 1; then
    echo "PostgreSQL user '${PGUSER}' already exists."
else
    echo "Creating PostgreSQL user '${PGUSER}'..."
    sudo -u postgres psql -c "CREATE USER ${PGUSER} WITH PASSWORD '${PGPASS}';"
    echo "User '${PGUSER}' created."
fi

# ---------------------------------------------------------------------------
# 5. Create databases and grant privileges
# ---------------------------------------------------------------------------
for DB in "${DATABASES[@]}"; do
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB}'" | grep -q 1; then
        echo "Database '${DB}' already exists."
    else
        echo "Creating database '${DB}'..."
        sudo -u postgres psql -c "CREATE DATABASE ${DB} OWNER ${PGUSER};"
        echo "Database '${DB}' created."
    fi

    # Grant all privileges (idempotent)
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB} TO ${PGUSER};" 2>/dev/null || true

    # Enable pgvector extension in each database (idempotent)
    sudo -u postgres psql -d "${DB}" -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>/dev/null || true
done

echo "=== PostgreSQL 16 provisioning complete ==="
