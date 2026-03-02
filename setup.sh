#!/bin/bash
set -e


# Config
WG_PORT=51820
WG_INTERFACE="wg0"
WG_SUBNET="10.0.0.0/24"
WG_SERVER_IP="10.0.0.1"
VPN_LAN_SUBNET="192.168.4.0/24"
REMAPPED_SUBNET="10.10.10.0/24"
CLIENT_COUNT=5


# Root check
if [ "$EUID" -ne 0 ]; then
  echo "Run with sudo."
  exit 1
fi
USER_HOME="/home/$SUDO_USER"


# Update and upgrade system
apt update && apt upgrade -y


# Install core depdencies / servies
apt install -y curl ufw fail2ban wireguard unattended-upgrades apt-listchanges


# Fail2Ban
systemctl enable --now fail2ban


# ENABLE AUTO SECURITY UPDATES
tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF


# Ufw firewall
ufw allow ssh
ufw allow ${WG_PORT}/udp
ufw --force enable


# Pull public ip
PUBLIC_IP=$(curl -s https://api.ipify.org)
ENDPOINT="${PUBLIC_IP}:${WG_PORT}"


# Pull lan interface (wifi or ethernet)
LAN_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
echo "LAN Interface: $LAN_IFACE"


# Enable ip forwarding
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard-forward.conf
sysctl --system


# Wireguard keys directory
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard
KEY_DIR="$USER_HOME/keys"
mkdir -p "$KEY_DIR"
cd "$KEY_DIR"


# Server keys
if [ ! -f server_privatekey ]; then
  wg genkey | tee server_privatekey | wg pubkey > server_publickey
fi
SERVER_PRIVATE_KEY=$(cat server_privatekey)
SERVER_PUBLIC_KEY=$(cat server_publickey)


# Client keys
for i in $(seq 1 $CLIENT_COUNT); do
  if [ ! -f client${i}_privatekey ]; then
    wg genkey | tee client${i}_privatekey | wg pubkey > client${i}_publickey
  fi
done


# Create wireguard server config
WG_CONF="/etc/wireguard/${WG_INTERFACE}.conf"
# Server info, postup, and postdown rules
cat > "$WG_CONF" <<EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = ${WG_SERVER_IP}/24
ListenPort = ${WG_PORT}

# Forward, MASQUERADE, and NETMAP for new custom local LAN
PostUp = \
iptables -A FORWARD -i %i -j ACCEPT; \
iptables -A FORWARD -o %i -j ACCEPT; \
iptables -t nat -A POSTROUTING -s ${WG_SUBNET} -o ${LAN_IFACE} -j MASQUERADE; \
iptables -t nat -A POSTROUTING -s ${WG_SUBNET} -o %i -j MASQUERADE; \
iptables -t nat -A PREROUTING -i %i -d ${REMAPPED_SUBNET} -j NETMAP --to ${VPN_LAN_SUBNET}; \
iptables -t nat -A POSTROUTING -s ${VPN_LAN_SUBNET} -o %i -j NETMAP --to ${REMAPPED_SUBNET}

PostDown = \
iptables -D FORWARD -i %i -j ACCEPT; \
iptables -D FORWARD -o %i -j ACCEPT; \
iptables -t nat -D POSTROUTING -s ${WG_SUBNET} -o ${LAN_IFACE} -j MASQUERADE; \
iptables -t nat -D POSTROUTING -s ${WG_SUBNET} -o %i -j MASQUERADE; \
iptables -t nat -D PREROUTING -i %i -d ${REMAPPED_SUBNET} -j NETMAP --to ${VPN_LAN_SUBNET}; \
iptables -t nat -D POSTROUTING -s ${VPN_LAN_SUBNET} -o %i -j NETMAP --to ${REMAPPED_SUBNET}
EOF
# Add peers to config file
for i in $(seq 1 $CLIENT_COUNT); do
  CLIENT_PUB=$(cat client${i}_publickey)
  CLIENT_IP="10.0.0.$((i+1))"
  cat >> "$WG_CONF" <<EOF
[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = ${CLIENT_IP}/32

EOF
done
# Set to owner only and enable startup
chmod 600 "$WG_CONF"
systemctl enable wg-quick@${WG_INTERFACE}


# Generrate client configs
CLIENT_DIR="$USER_HOME/client-configs"
mkdir -p "$CLIENT_DIR"
for i in $(seq 1 $CLIENT_COUNT); do
  CLIENT_PRIV=$(cat client${i}_privatekey)
  CLIENT_IP="10.0.0.$((i+1))"
  cat > "${CLIENT_DIR}/client${i}.conf" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV
Address = ${CLIENT_IP}/24
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = ${ENDPOINT}
AllowedIPs = ${WG_SUBNET}, ${REMAPPED_SUBNET}
PersistentKeepalive = 25
EOF
done


# CLEANUP & REBOOT
apt autoremove -y
echo "Setup complete."
echo "VPN LAN ${VPN_LAN_SUBNET} is exposed as ${REMAPPED_SUBNET} to VPN clients"
echo "Client configs are in ${CLIENT_DIR}"
echo "Keys are in ${KEY_DIR}"
echo "Rebooting..."
reboot