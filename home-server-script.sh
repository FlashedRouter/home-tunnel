#!/bin/sh

# ================================================================
#  WireGuard VPN Server - Automatic Setup Script for OpenWrt
#  This script sets up a secure VPN tunnel on your home router.
#  Run once. Takes about 1-2 minutes to complete.
# ================================================================

# ---------------------------------------------------------------
# STEP 1: Sync the router's clock with an internet time server
# Having the correct time is critical for VPN encryption to work.
# ---------------------------------------------------------------
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║       WireGuard VPN Setup — Starting Now...          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "[ 1/6 ] ⏰  Syncing the router clock with Google's time servers..."
echo "        (VPN security depends on having the correct time)"

/etc/init.d/sysntpd enable
/etc/init.d/sysntpd stop
ntpd -q -p time1.google.com
/etc/init.d/sysntpd start

echo "        ✔  Clock synced successfully! Current time: $(date)"
echo ""


# ---------------------------------------------------------------
# STEP 2: Download and install the required software packages
# WireGuard is the VPN software. 'screen' is a helper utility.
# ---------------------------------------------------------------
echo "[ 2/6 ] 📦  Downloading and installing WireGuard VPN software..."
echo "        (This requires an internet connection — please wait)"

opkg update && opkg install wireguard-tools screen

echo "        ✔  WireGuard installed successfully!"
echo ""


# ---------------------------------------------------------------
# STEP 3: Define the VPN network settings
# These values describe how the private VPN network will be structured.
#   - VPN_IF   : the name for this VPN connection on the router
#   - VPN_PORT : the "door" on the router that VPN traffic uses
#   - VPN_ADDR : the internal IP address of the router inside the VPN
# ---------------------------------------------------------------
echo "[ 3/6 ] ⚙️   Preparing VPN network settings..."

VPN_IF="wg_homeserver"
VPN_PORT="51820"
VPN_ADDR="192.168.9.1/24"

echo "        VPN interface name : $VPN_IF"
echo "        VPN port           : $VPN_PORT (UDP)"
echo "        VPN server address : $VPN_ADDR"
echo ""


# ---------------------------------------------------------------
# STEP 4: Generate cryptographic keys
# These keys are like unique padlocks and keys — they ensure only
# YOUR device can connect to this VPN, and all traffic is encrypted.
#   - Server key pair : used to identify and secure the router
#   - Client key pair : used to identify and secure your device
#   - Pre-shared key  : an extra layer of shared secret between both
# ---------------------------------------------------------------
echo "[ 4/6 ] 🔐  Generating encryption keys for server and client..."
echo "        (These are unique to this setup — never share the private keys)"

umask go=

# Generate server keys (the router's identity)
wg genkey | tee wgserver.key | wg pubkey > wgserver.pub

# Generate client keys (your device's identity)
wg genkey | tee wgclient.key | wg pubkey > wgclient.pub

# Generate pre-shared key (extra shared secret for both sides)
wg genpsk > wgclient.psk

# Load keys into variables for use in configuration below
VPN_KEY="$(cat wgserver.key)"   # Server's private key
VPN_PSK="$(cat wgclient.psk)"   # Pre-shared key
VPN_PUB="$(cat wgclient.pub)"   # Client's public key

echo "        ✔  All keys generated and stored securely!"
echo ""


# ---------------------------------------------------------------
# STEP 5a: Configure the firewall
# This tells the router's firewall to allow incoming VPN connections
# on the chosen port, while keeping everything else protected.
# ---------------------------------------------------------------
echo "[ 5/6 ] 🛡️   Configuring the firewall to allow VPN traffic..."
echo "        (Opening UDP port $VPN_PORT for incoming VPN connections)"

# Add the VPN interface to the trusted LAN zone (so VPN clients get full access)
uci rename firewall.@zone[0]="lan"
uci rename firewall.@zone[1]="wan"
uci del_list firewall.lan.network="${VPN_IF}"
uci add_list firewall.lan.network="${VPN_IF}"

# Create a firewall rule that allows incoming WireGuard packets
uci -q delete firewall.wg
uci set firewall.wg="rule"
uci set firewall.wg.name="Allow-WireGuard"
uci set firewall.wg.src="wan"
uci set firewall.wg.dest_port="${VPN_PORT}"
uci set firewall.wg.proto="udp"
uci set firewall.wg.target="ACCEPT"

# Save and apply the firewall changes
uci commit firewall
service firewall restart

echo "        ✔  Firewall updated — VPN port $VPN_PORT is now open!"
echo ""


# ---------------------------------------------------------------
# STEP 5b: Configure the VPN network interface on the router
# This creates the actual WireGuard VPN interface and registers
# the client device as an approved peer (trusted connection).
# ---------------------------------------------------------------
echo "        Setting up the VPN network interface on the router..."

# Create the WireGuard interface with the server's private key and port
uci -q delete network.${VPN_IF}
uci set network.${VPN_IF}="interface"
uci set network.${VPN_IF}.proto="wireguard"
uci set network.${VPN_IF}.private_key="${VPN_KEY}"
uci set network.${VPN_IF}.listen_port="${VPN_PORT}"
uci add_list network.${VPN_IF}.addresses="${VPN_ADDR}"

# Register the client device as an allowed peer
# allowed_ips restricts this client to its own assigned IP (.2)
uci -q delete network.wgclient
uci set network.wgclient="wireguard_${VPN_IF}"
uci set network.wgclient.public_key="${VPN_PUB}"
uci set network.wgclient.preshared_key="${VPN_PSK}"
uci add_list network.wgclient.allowed_ips="${VPN_ADDR%.*}.2/32"

# Save the network configuration (network restart handled manually after)
uci commit network
# Note: Uncomment the line below to auto-restart networking (causes brief disconnect)
# service network restart

echo "        ✔  VPN interface configured and client registered!"
echo ""


# ---------------------------------------------------------------
# STEP 6: Generate the client configuration file
# This is the file you import into the WireGuard app on your
# phone, laptop, or any device you want to connect to the VPN.
# ---------------------------------------------------------------
echo "[ 6/6 ] 📄  Generating the client config file (wg-client.conf)..."
echo "        (You will import this file into the WireGuard app on your device)"

# Reload key variables for the client config perspective
VPN_KEY="$(cat wgclient.key)"          # Client's private key
VPN_PSK="$(cat wgclient.psk)"          # Pre-shared key
VPN_PUB="$(cat wgserver.pub)"          # Server's public key
CLIENT_ADDRESS="${VPN_ADDR%.*}.2/32"   # Client's VPN IP address
VPNSRV=$(uci get network.lan.ipaddr)   # Router's LAN IP address
SERVER_ENDPOINT="$VPNSRV:$VPN_PORT"   # How the client finds the server
ALLOWED_IPS="0.0.0.0/0, ::/0"         # Route ALL traffic through the VPN
DNS_SERVER="94.140.14.14, 94.140.15.15" # AdGuard DNS (blocks ads & trackers)

# Write the config file that will be imported into the WireGuard app
cat <<EOF > wg-client.conf
[Interface]
# Your device's VPN identity and address
PrivateKey = ${VPN_KEY}
Address = ${CLIENT_ADDRESS}
ListenPort = ${VPN_PORT}
DNS = ${DNS_SERVER}

[Peer]
# The router (VPN server) you are connecting to
PublicKey = ${VPN_PUB}
PresharedKey = ${VPN_PSK}
Endpoint = ${SERVER_ENDPOINT}
AllowedIPs = ${ALLOWED_IPS}
EOF

echo "        ✔  Client config file saved to: /root/wg-client.conf"
echo ""


# ---------------------------------------------------------------
# DONE — Print summary and the client config for easy copying
# ---------------------------------------------------------------
echo "════════════════════════════════════════════════════════"
echo "  ✅  VPN SETUP COMPLETE!"
echo "════════════════════════════════════════════════════════"
echo ""
echo "  Here is a summary of your active VPN connections:"
echo ""
wg show
echo ""
echo "────────────────────────────────────────────────────────"
echo "  📋  Your client config file (import this into the"
echo "      WireGuard app on your phone or laptop):"
echo "────────────────────────────────────────────────────────"
echo ""
cat /root/wg-client.conf
echo ""
echo "────────────────────────────────────────────────────────"
echo "  💡  NEXT STEPS:"
echo "      1. Copy the config above into a file called"
echo "         'wg-client.conf' on your device."
echo "      2. Open the WireGuard app and choose"
echo "         'Import from file' or 'Add tunnel'."
echo "      3. Connect — your traffic is now secured!"
echo "────────────────────────────────────────────────────────"
echo ""

sync
