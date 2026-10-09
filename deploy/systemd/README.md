# eShop Systemd Service Units

This directory contains systemd unit files for deploying eShop application services on Ubuntu 24.04 with native systemd service management.

## Overview

The eShop application is composed of multiple .NET services, each managed as an individual systemd unit. All services are grouped under `eshop.target`, allowing unified start/stop/status operations.

## Architecture

```
multi-user.target
  └── eshop.target
        ├── eshop-payment-processor.service
        ├── eshop-order-processor.service
        └── (additional services added in subsequent milestones)
```

## Dependency Chain

Infrastructure services (managed separately by their own packages) are required before eShop application services start:

| Infrastructure Service     | Systemd Unit              | Depended On By                     |
|----------------------------|---------------------------|------------------------------------|
| PostgreSQL                 | `postgresql.service`      | Order Processor, and future API services |
| RabbitMQ                   | `rabbitmq-server.service` | Payment Processor, Order Processor |
| Redis                      | `redis-server.service`    | Future API services (Basket, etc.) |

Application services declare their infrastructure dependencies via `After=` and `Requires=` directives. The `eshop.target` groups all application services and waits for all infrastructure services.

## Installation

1. Copy the unit files to the systemd directory:

   ```bash
   sudo cp deploy/systemd/*.service /etc/systemd/system/
   sudo cp deploy/systemd/eshop.target /etc/systemd/system/
   ```

2. Create the environment file from the template:

   ```bash
   sudo mkdir -p /etc/eshop
   sudo cp deploy/eshop.env.template /etc/eshop/eshop.env
   sudo chmod 600 /etc/eshop/eshop.env
   sudo chown eshop:eshop /etc/eshop/eshop.env
   ```

3. Edit `/etc/eshop/eshop.env` with the correct connection strings and passwords for your environment.

4. Reload systemd and enable the target:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable eshop.target
   ```

5. Enable individual services:

   ```bash
   sudo systemctl enable eshop-payment-processor.service
   sudo systemctl enable eshop-order-processor.service
   ```

## Common Commands

### Start/Stop All eShop Services

```bash
# Start all eShop services
sudo systemctl start eshop.target

# Stop all eShop services
sudo systemctl stop eshop.target

# Check status of all eShop services
sudo systemctl status eshop.target
```

### Manage Individual Services

```bash
# Start a specific service
sudo systemctl start eshop-payment-processor.service

# Stop a specific service
sudo systemctl stop eshop-order-processor.service

# Restart a specific service
sudo systemctl restart eshop-payment-processor.service

# Check status of a specific service
sudo systemctl status eshop-order-processor.service
```

### View Logs

```bash
# View logs for all eShop services
journalctl -u eshop-*

# View logs for a specific service
journalctl -u eshop-payment-processor.service

# Follow logs in real time
journalctl -u eshop-payment-processor.service -f

# View logs since last boot
journalctl -u eshop-order-processor.service -b

# View logs from the last hour
journalctl -u eshop-* --since "1 hour ago"
```

## Environment File Pattern

All eShop services share a single environment file at `/etc/eshop/eshop.env`. This file is referenced by each service unit via the `EnvironmentFile=` directive.

The template is provided at `deploy/eshop.env.template`. Key points:

- The file contains connection strings for PostgreSQL, RabbitMQ, and Redis
- Service URLs for inter-service communication are configured here
- The file should have restricted permissions (`chmod 600`) since it contains credentials
- Changes to the environment file require restarting affected services

## How to Add a New Service Unit

When adding a new eShop microservice, follow this pattern:

1. Create a new file named `eshop-<service-name>.service` in this directory.

2. Use the following template:

   ```ini
   [Unit]
   Description=eShop <Service Name> Service
   After=network.target <infrastructure-dependencies>
   Requires=<infrastructure-dependencies>
   PartOf=eshop.target

   [Service]
   Type=exec
   EnvironmentFile=/etc/eshop/eshop.env
   WorkingDirectory=/opt/eshop/<ServiceName>
   ExecStart=/usr/bin/dotnet <ServiceName>.dll
   ExecStartPost=/bin/bash -c 'retries=0; until curl -sf http://localhost:<PORT>/health > /dev/null 2>&1 || [ $retries -ge 30 ]; do sleep 2; retries=$((retries+1)); done; curl -sf http://localhost:<PORT>/health > /dev/null 2>&1'
   Restart=on-failure
   RestartSec=10
   User=eshop
   Group=eshop

   # Security hardening
   NoNewPrivileges=true
   ProtectSystem=strict
   ProtectHome=true
   ReadWritePaths=/opt/eshop/<ServiceName>

   # Logging
   StandardOutput=journal
   StandardError=journal
   SyslogIdentifier=eshop-<service-name>

   [Install]
   WantedBy=eshop.target
   ```

3. Replace the placeholders:
   - `<Service Name>`: Human-readable name (e.g., "Catalog API")
   - `<ServiceName>`: Directory and DLL name (e.g., "Catalog.API")
   - `<service-name>`: Lowercase hyphenated name for the unit file (e.g., "catalog-api")
   - `<PORT>`: The port the service listens on
   - `<infrastructure-dependencies>`: Space-separated list of required infrastructure units (e.g., `postgresql.service rabbitmq-server.service`)

4. Install and enable:

   ```bash
   sudo cp eshop-<service-name>.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable eshop-<service-name>.service
   ```

5. Add any new environment variables the service needs to `/etc/eshop/eshop.env`.

## Security Hardening

Each service unit includes basic security hardening directives:

- `NoNewPrivileges=true` - Prevents the service from gaining new privileges
- `ProtectSystem=strict` - Mounts the file system as read-only except for explicitly allowed paths
- `ProtectHome=true` - Makes home directories inaccessible
- `ReadWritePaths=` - Explicitly allows write access only to the service's working directory
- `User=eshop` / `Group=eshop` - Runs under a dedicated non-root user

## Health Checking

Each service includes an `ExecStartPost` directive that performs a health check after startup. The check:

- Retries up to 30 times with a 2-second delay between attempts (up to 60 seconds total)
- Hits the `/health` endpoint on the service's configured port
- Fails the service start if the health check does not pass within the retry window
