## Deprecated

This project is archived in favor of [ssh_tunnel](https://github.com/aleskxyz/ssh_tunnel).

To remove your current installation, run the following commands:

```bash
for i in $(systemctl list-units --no-legend --no-pager 'reverse-ssh-*' | awk '{print $1}'); do
  systemctl disable --now "$i"
done
sudo systemctl reset-failed
rm -f /etc/systemd/system/reverse-ssh-* /etc/ssh/reverse_ssh_tunnel*
```

# Reverse SSH Tunnel Setup

A robust script for setting up and maintaining reverse SSH tunnels with automatic health checking.

## 🌟 Features

- **One-Command Setup**: Configure both local and remote servers with a single command
- **Idempotent**: Safe to run multiple times without side effects
- **Secure**: Uses ED25519 SSH keys and proper file permissions
- **Persistent**: Sets up systemd service for automatic tunnel maintenance
- **Multi-Service Support**: Configure multiple services on the same remote server
- **Beautiful Output**: Color-coded status messages and clear progress indicators
- **Automatic Health Checking**: Checks tunnel accessibility every 10 seconds
- **Automatic Tunnel Restart**: Restarts tunnel if connection is lost

## 📋 Prerequisites

- Bash shell
- Sudo privileges on both local and remote servers
- SSH access to the remote server
- Systemd (for service management)
- `netcat` (nc) installed on the system

## 🚀 Installation

### Quick Start (One-Line Command)

```bash
bash <(curl -sSL https://raw.githubusercontent.com/aleskxyz/reverse_ssh_tunnel/main/setup_tunnel.sh) root@192.168.1.100:22 -s 443
```

This command will:
1. Download the script
2. Set up the reverse tunnel

You can also specify an SSH key:
```bash
bash <(curl -sSL https://raw.githubusercontent.com/aleskxyz/reverse_ssh_tunnel/main/setup_tunnel.sh) root@192.168.1.100:22 -s 443 -i ~/.ssh/id_rsa
```

### Manual Installation

1. Download the script:
```bash
curl -O https://raw.githubusercontent.com/aleskxyz/reverse_ssh_tunnel/main/setup_tunnel.sh
```

2. Make it executable:
```bash
chmod +x setup_tunnel.sh
```

## 💻 Usage

```bash
./setup_tunnel.sh USER@HOST[:PORT] -s SERVICE_PORT [-i SSH_KEY]
```

### Arguments

- `USER@HOST[:PORT]`: Connection string for the remote server
  - Example: `root@192.168.1.100:22`
  - Port is optional (defaults to 22)

- `-s SERVICE_PORT`: Port for the reverse SSH tunnel service
  - Example: `-s 443`

- `-i SSH_KEY`: (Optional) Path to SSH key for authentication
  - Example: `-i ~/.ssh/id_rsa`

- `-h, --help`: Show help message

### Example

```bash
./setup_tunnel.sh root@192.168.1.100:22 -s 443 -i ~/.ssh/id_rsa
```

## 🔧 What the Script Does

1. **Local Setup**:
   - Generates ED25519 SSH keypair
   - Sets up systemd service for the reverse tunnel
   - Configures automatic tunnel maintenance

2. **Remote Setup**:
   - Configures SSH server for reverse tunneling
   - Injects the public key
   - Sets up necessary SSH configurations

3. **Tunnel Configuration**:
   - Creates persistent reverse SSH tunnel
   - Enables automatic reconnection
   - Configures proper port forwarding

## 🔍 Health Check

The script sets up a systemd timer that:
- Runs every 10 seconds
- Checks if the tunnel is accessible using netcat
- Automatically restarts the tunnel if the check fails
- Starts automatically with the system

## 📝 License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## 🔧 Troubleshooting

If you encounter any issues:

1. Ensure `netcat` is installed on your system
2. Check if you have sudo access
3. Verify the remote host is accessible
4. Check the systemd service status:
```bash
systemctl status reverse-ssh-tunnel@<PORT>.service
systemctl status reverse-ssh-healthcheck@<PORT>.timer
```
