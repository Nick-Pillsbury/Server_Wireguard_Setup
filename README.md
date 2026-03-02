# WireGuard VPN Setup Script

WireGuard VPN server deployment for Debian Linux.

This script:
- Installs and configures WireGuard
- Configures firewall (UFW)
- Enables IP forwarding
- Generates server + multiple client keys
- Creates client config files automatically
- Exposes your local LAN to VPN clients using NETMAP
- Enables security services (Fail2Ban, unattended upgrades)
- Auto-detects public IP and preferred network interface
- Removes unused packages and Reboots when finished

---

# What The Script Installs
- WireGuard
- UFW firewall
- Fail2Ban (SSH protection)
- Unattended security updates
- apt-listchanges

---

## Firewall Rules
UFW automatically allows:
- SSH (22)
- WireGuard (51820/UDP)

---

## Config Variables
These are the variables that need to be changed to work with individual setups.
```bash
# Port that wireguard setup is exposed on
WG_PORT=51820
```
```bash
# Interface name for wireguard setup
WG_INTERFACE="wg0"
```
```bash
# Subnet for wireguard users
WG_SUBNET="10.0.0.0/24"
```
```bash
# Server ip in wireguard subnet
WG_SERVER_IP="10.0.0.1"
```
```bash
# Subnet of the local lan that the server is on
VPN_LAN_SUBNET="192.168.4.0/24"
```
```bash
# Subnet that local lan will be remapped to
REMAPPED_SUBNET="10.10.10.0/24"
```
```bash
# Number of clients that will be generated / added
CLIENT_COUNT=5
```

---

## What Gets Generated
### Client Config Files
Located in:
```bash 
/home/<your-user>/client-configs/
```
Files:
- client1.conf
- client2.conf
- client3.conf
- client4.conf
- client5.conf
- ...
### Keys
Located in:
```bash
/home/<your-user>/keys/
```
Files:
- server_publickey
- server_privatekey
- client1_publickey
- client1_privatekey
- client2_publickey
- client2_privatekey
- ...
### Server config
Located at:
```bash
/etc/wireguard/wg0.conf
```

---

## Network Architecture
### VPN Network
- VPN Subnet: `10.0.0.0/24`
- Server VPN IP: `10.0.0.1`
- Clients: `10.0.0.2 – 10.0.0.6` (default 5 clients)
### Local LAN (Server Side)
- Real LAN: `192.168.4.0/24`
- Exposed to VPN as: `10.10.10.0/24`

This means:
| Real LAN        | Appears To VPN Clients As |
|-----------------|--------------------------|
| 192.168.4.10    | 10.10.10.10              |
| 192.168.4.50    | 10.10.10.50              |

This avoids subnet conflicts when the local lan of clients is the same as the local lan of the server.

---

## How Client Routing Works
### AllowedIPs = 10.0.0.0/24
This means:
- VPN subnet traffic goes through tunnel
- On a vpn lan with all other clients
- Internet traffic stays local (split tunnel)
### AllowedIPs = 10.10.10.0/24
This means:
- Remapped LAN goes through tunnel
- Internet traffic stays local (split tunnel)
### AllowedIPs = 0.0.0.0/0
This means:
- Full tunnel instead, all traffic goes through vpn
- Access to VPN subnet and local lan
- Traffic is masqueraded as server
### What to use in client config
- AllowedIPs = 10.0.0.0/24
- AllowedIPs = 10.0.0.0/24, 10.10.10.0/24
- AllowedIPs = 0.0.0.0/0

---

## How To Use
### Copy Script To Server
```bash
scp setup.sh user@server-ip:~
```
### Run Script
```bash
chmod +x setup.sh
sudo ./setup.sh
```

---

## Re-running Script
If re-run:
- Existing keys are preserved
- Existing configs are overwritten
- Missing client keys are generated
- WireGuard config is regenerated

---

## Requirements
- Port must be forwarded on your router to server.
    - Script assumes that port on router and port on server are the same
    - If they are not change client configs to, \<PUBLIC_IP\>:\<ROUTER_PORT\>
    - Make sure that port forward is: \<PUBLIC_IP\>:\<ROUTER_PORT\> to \<SERVER_IP\>:\<WG_PORT\>
- Server must have a static local IP.
- The REMAPPED_SUBNET must NOT overlap with:
    - The server lan
    - The vpn subnet
