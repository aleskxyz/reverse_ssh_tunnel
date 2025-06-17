#!/bin/bash
#
# Reverse SSH Tunnel Setup Script
# Copyright (C) 2024
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# For more information about this license, visit:
# https://www.gnu.org/licenses/gpl-3.0.html

# Exit on error and undefined variables
set -e
set -u

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'
DIM='\033[2m'

# Constants
KEY_PATH="/etc/ssh/reverse_ssh_tunnel"
SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
REVERSE_SSH_CONFIG="${SSHD_CONFIG_DIR}/zzz_reverse_ssh_tunnel.conf"
REVERSE_TUNNEL_SERVICE="/etc/systemd/system/reverse-ssh-tunnel@.service"
REVERSE_HEALTHCHECK_SERVICE="/etc/systemd/system/reverse-ssh-healthcheck@.service"
REVERSE_HEALTHCHECK_TIMER="/etc/systemd/system/reverse-ssh-healthcheck@.timer"

# Function to print status messages
print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        "info")    echo -e "${BLUE}ℹ ${message}${NC}" ;;
        "success") echo -e "${GREEN}✓ ${message}${NC}" ;;
        "warning") echo -e "${YELLOW}⚠ ${message}${NC}" ;;
        "error")   echo -e "${RED}✗ ${message}${NC}" ;;
    esac
}

# Function to print section headers
print_section() {
    echo -e "\n${BOLD}${BLUE}==>${NC} ${BOLD}$1${NC}"
}

# Function to show help
show_help() {
    cat << EOF
${BOLD}Reverse SSH Tunnel Setup Script${NC}

${DIM}Usage:${NC} $0 USER@HOST[:PORT] -s SERVICE_PORT [-i SSH_KEY]

${BOLD}Arguments:${NC}
  ${GREEN}USER@HOST[:PORT]${NC}    Connection string (e.g., root@192.168.1.100:22)
  ${GREEN}-s SERVICE_PORT${NC}     Port for the reverse SSH tunnel service
  ${GREEN}-i SSH_KEY${NC}         Path to SSH key for authentication (optional)
  ${GREEN}-h, --help${NC}         Show this help message

${BOLD}Example:${NC}
  $0 root@192.168.1.100:22 -s 443 -i ~/.ssh/id_rsa

${BOLD}Description:${NC}
  This script will:
  1. Configure the remote server for reverse SSH tunneling
  2. Generate SSH key and inject it into the remote server
  3. Configure the local server to accept the reverse tunnel
  4. Set up a persistent reverse SSH tunnel service
  5. Idempotent, so you can run it multiple times without issues
  6. Configure for multiple services on the same remote server
EOF
    exit 0
}

# Function to handle errors
handle_error() {
    print_status "error" "$1"
    exit 1
}

# Function to check sudo access
check_sudo_access() {
    print_section "Checking sudo access"
    if ! sudo -v; then
        handle_error "Sudo access required. Please ensure you have sudo privileges."
    fi
    print_status "success" "Sudo access verified"
}

# Function to check netcat availability
check_netcat() {
    print_section "Checking netcat availability"
    if ! command -v nc >/dev/null 2>&1; then
        handle_error "Netcat (nc) is not installed. Please install it before running this script."
    fi
    print_status "success" "Netcat is available"
}

# Function to generate SSH keypair
generate_ssh_key() {
    print_section "Generating SSH keypair"
    
    # Check if key already exists and is valid
    if sudo test -f "$KEY_PATH" && sudo test -f "$KEY_PATH.pub"; then
        # Verify the key is readable and has correct permissions
        if sudo test -r "$KEY_PATH" && [ "$(sudo stat -c %a "$KEY_PATH")" = "600" ]; then
            print_status "info" "SSH keypair already exists and has correct permissions"
            return 0
        else
            print_status "warning" "Fixing permissions on existing SSH keypair"
            sudo chmod 600 "$KEY_PATH"
            sudo chmod 644 "$KEY_PATH.pub"
            return 0
        fi
    fi
    
    print_status "info" "Generating new SSH keypair"
    sudo ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "" -q
    
    if [ $? -eq 0 ]; then
        print_status "success" "SSH keypair generated successfully"
        sudo chmod 600 "$KEY_PATH"
        sudo chmod 644 "$KEY_PATH.pub"
    else
        handle_error "Failed to generate SSH keypair"
    fi
}

# Function to configure SSH server
configure_ssh_server() {
    print_section "Configuring SSH server on remote host"

    # Create the configuration script
    local config_script=$(cat << EOF
#!/bin/bash
set -e
set -u

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# Function to print status messages
print_status() {
    local status="\$1"
    local message="\$2"
    case "\$status" in
        "info")    echo -e "\${BLUE}ℹ \${message}\${NC}" ;;
        "success") echo -e "\${GREEN}✓ \${message}\${NC}" ;;
        "warning") echo -e "\${YELLOW}⚠ \${message}\${NC}" ;;
        "error")   echo -e "\${RED}✗ \${message}\${NC}" ;;
    esac
}

SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
REVERSE_SSH_CONFIG="\${SSHD_CONFIG_DIR}/zzz_reverse_ssh_tunnel.conf"
NEEDS_RESTART=false

# Check if sudo access is available
if ! sudo -n true > /dev/null 2>&1; then
    print_status "error" "Passwordless sudo access required on remote host."
    exit 1
fi

# Create config directory if it doesn't exist
sudo mkdir -p "$SSHD_CONFIG_DIR"


# Add Include directive if it doesn't exist
if ! sudo grep -q "^Include.*sshd_config.d/\*.conf" "/etc/ssh/sshd_config"; then
    print_status "info" "Adding Include directive to main SSH config"
    echo -e "\n# Include additional configuration files\nInclude $SSHD_CONFIG_DIR/*.conf" | sudo tee -a "/etc/ssh/sshd_config" > /dev/null
    NEEDS_RESTART=true
fi

# Define the expected configuration
expected_config="GatewayPorts yes
AllowTcpForwarding yes
PermitRootLogin yes"

# Check if configuration file exists and has correct content
if [ -f "\$REVERSE_SSH_CONFIG" ]; then
    current_config=\$(sudo cat "\$REVERSE_SSH_CONFIG")
    if [ "\$current_config" != "\$expected_config" ]; then
        print_status "info" "Creating reverse SSH configuration"
        echo "\$expected_config" | sudo tee "\$REVERSE_SSH_CONFIG" > /dev/null
        sudo chmod 644 "\$REVERSE_SSH_CONFIG"
        NEEDS_RESTART=true
    fi
else
    print_status "info" "Creating reverse SSH configuration"
    echo "\$expected_config" | sudo tee "\$REVERSE_SSH_CONFIG" > /dev/null
    sudo chmod 644 "\$REVERSE_SSH_CONFIG"
    NEEDS_RESTART=true
fi

# Configure authorized_keys
print_status "info" "Configuring authorized_keys"
sudo mkdir -p /root/.ssh
sudo chmod 700 /root/.ssh

# Check if key is already in authorized_keys
if ! sudo grep -q "$PUBLIC_KEY" /root/.ssh/authorized_keys 2>/dev/null; then
    echo "$PUBLIC_KEY" | sudo tee -a /root/.ssh/authorized_keys > /dev/null
    sudo chmod 600 /root/.ssh/authorized_keys
    sudo chown root:root /root/.ssh/authorized_keys
    print_status "success" "Public key added to authorized_keys"
else
    print_status "info" "Public key already exists in authorized_keys"
fi

# Restart SSH service only if needed
if [ "\$NEEDS_RESTART" = true ]; then
    print_status "info" "Restarting SSH service due to configuration changes"
    sudo systemctl restart ssh
else
    print_status "info" "No configuration changes needed, skipping SSH service restart"
fi

print_status "success" "SSH server configuration completed successfully"
EOF
)

    # Build SSH command with optional key
    ssh_cmd=(
        ssh
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
    )
    if [ -n "$SSH_KEY" ]; then
        ssh_cmd+=(-i "$SSH_KEY")
    fi
    ssh_cmd+=("-p" "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_HOST}" "bash -s")

    # Execute the command
    "${ssh_cmd[@]}" <<< "$config_script"
}

# Function to setup reverse SSH tunnel
setup_reverse_tunnel() {
    print_section "Setting up reverse SSH tunnel"
    
    # Define the expected service content
    local expected_content
    expected_content=$(cat << EOF
[Unit]
Description=Reverse SSH Tunnel for port %i
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/ssh -i ${KEY_PATH} \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=60 \
  -o ExitOnForwardFailure=yes \
  -N -R 0.0.0.0:%i:localhost:%i root@${REMOTE_HOST} -p ${REMOTE_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
)

    # Define the healthcheck service content
    local healthcheck_content
    healthcheck_content=$(cat << EOF
[Unit]
Description=Health check for reverse SSH tunnel on port %i
Wants=reverse-ssh-tunnel@%i.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'nc -z -w 5 ${REMOTE_HOST} %i || systemctl restart reverse-ssh-tunnel@%i.service'
EOF
)

    # Define the healthcheck timer content
    local timer_content
    timer_content=$(cat << EOF
[Unit]
Description=Run SSH tunnel health check on port %i every 10s

[Timer]
OnBootSec=10
OnUnitActiveSec=10s
AccuracySec=1s
Unit=reverse-ssh-healthcheck@%i.service

[Install]
WantedBy=timers.target
EOF
)

    # Get current service content if file exists
    local service_content=""
    if sudo test -f "$REVERSE_TUNNEL_SERVICE"; then
        service_content=$(sudo cat "$REVERSE_TUNNEL_SERVICE")
    fi

    # Check if service file needs to be created or updated
    local needs_reload=false
    if [ "$service_content" != "$expected_content" ]; then
        print_status "info" "Creating/updating systemd service"
        echo "$expected_content" | sudo tee "$REVERSE_TUNNEL_SERVICE" > /dev/null
        needs_reload=true
    else
        print_status "info" "Service file already exists and is correctly configured"
    fi

    # Create/update healthcheck service
    print_status "info" "Creating/updating healthcheck service"
    echo "$healthcheck_content" | sudo tee "$REVERSE_HEALTHCHECK_SERVICE" > /dev/null
    needs_reload=true

    # Create/update healthcheck timer
    print_status "info" "Creating/updating healthcheck timer"
    echo "$timer_content" | sudo tee "$REVERSE_HEALTHCHECK_TIMER" > /dev/null
    needs_reload=true

    # Reload systemd if needed
    if [ "$needs_reload" = true ]; then
        print_status "info" "Reloading systemd"
        sudo systemctl daemon-reload
    fi
    
    # Get current service state
    local service_name="reverse-ssh-tunnel@${SERVICE_PORT}"
    local healthcheck_timer="reverse-ssh-healthcheck@${SERVICE_PORT}.timer"
    local is_enabled=$(sudo systemctl is-enabled "$service_name" 2>/dev/null || echo "disabled")
    
    # Enable service if not enabled
    if [ "$is_enabled" != "enabled" ]; then
        print_status "info" "Enabling reverse tunnel service"
        sudo systemctl enable "$service_name"
    else
        print_status "info" "Service is already enabled"
    fi

    # Enable and start healthcheck timer
    print_status "info" "Enabling and starting healthcheck timer"
    sudo systemctl enable --now "$healthcheck_timer"
    
    # Try to start the service, but don't fail if it doesn't start
    print_status "info" "Starting reverse tunnel service"
    sudo systemctl start "$service_name" || true
    
    print_status "success" "Reverse SSH tunnel setup completed successfully"
}

# Main script
if [ $# -eq 0 ]; then
    show_help
fi

# Parse arguments
CONNECTION_STRING=""
SERVICE_PORT=""
SSH_KEY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--service)
            SERVICE_PORT="$2"
            shift 2
            ;;
        -i|--identity)
            SSH_KEY="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            if [ -z "$CONNECTION_STRING" ]; then
                CONNECTION_STRING="$1"
            else
                handle_error "Unexpected argument: $1"
            fi
            shift
            ;;
    esac
done

# Validate required arguments
if [ -z "$CONNECTION_STRING" ]; then
    handle_error "Connection string is required"
fi

if [ -z "$SERVICE_PORT" ]; then
    handle_error "Service port is required"
fi

# Parse connection string
if [[ $CONNECTION_STRING =~ ^([^@]+)@([^:]+)(:([0-9]+))?$ ]]; then
    REMOTE_USER="${BASH_REMATCH[1]}"
    REMOTE_HOST="${BASH_REMATCH[2]}"
    REMOTE_PORT="${BASH_REMATCH[4]:-22}"
else
    handle_error "Invalid connection string format. Expected format: user@host[:port]"
fi

# Check sudo access
check_sudo_access

# Check netcat availability
check_netcat

# Generate SSH keypair
generate_ssh_key

# Get the public key
PUBLIC_KEY=$(sudo cat ${KEY_PATH}.pub | tr -d '\n' | sed 's/[[:space:]]*$//')

# Configure SSH server on remote host and inject public key
configure_ssh_server

# Setup reverse tunnel
setup_reverse_tunnel

print_section "Setup Summary"
print_status "success" "Setup completed successfully"
echo -e "${BOLD}Connection Information:${NC}"
echo -e "  ${DIM}Remote Host:${NC} ${GREEN}${REMOTE_HOST}${NC}"
echo -e "  ${DIM}Service Port:${NC} ${GREEN}${SERVICE_PORT}${NC}"
echo -e "  ${DIM}SSH Port:${NC} ${GREEN}${REMOTE_PORT}${NC}"
echo -e "\n${BOLD}You can now connect to the service on:${NC} ${GREEN}${REMOTE_HOST}:${SERVICE_PORT}${NC}"
