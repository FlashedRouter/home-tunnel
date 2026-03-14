#!/bin/sh

# ================================================================
#  Home VPN Server — Full Setup Script for OpenWrt
#  ----------------------------------------------------------------
#  This script does everything needed to turn your OpenWrt router
#  into a secure WireGuard VPN server that you can connect to
#  from anywhere in the world.
#
#  What it does, in order:
#    Part 1 — VPN setup      : installs WireGuard, generates keys,
#                               configures the firewall, and creates
#                               a ready-to-import client config file
#    Part 2 — Network setup  : renames the router, sets its IP,
#                               and configures local DNS
#
#  Run once. Takes about 2-3 minutes to complete.
# ================================================================

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║       Home VPN Server — Full Setup Starting...       ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  This will install WireGuard and configure your router."
echo "  Please do not close this session until it is finished."
echo ""
echo "════════════════════════════════════════════════════════"
echo "  PART 1 OF 2 — WireGuard VPN Server Setup"
echo "════════════════════════════════════════════════════════"
echo ""


# ---------------------------------------------------------------
# STEP 1: Sync the router's clock with an internet time server
# Having the correct time is critical for VPN encryption to work.
# If the router's clock is wrong, VPN handshakes will fail.
# ---------------------------------------------------------------
echo "[ 1/10 ] ⏰  Syncing the router clock with Google's time servers..."
echo "         (VPN security depends on having the correct time)"

/etc/init.d/sysntpd enable
/etc/init.d/sysntpd stop
ntpd -q -p time1.google.com
/etc/init.d/sysntpd start

echo "         ✔  Clock synced! Current time: $(date)"
echo ""


# ---------------------------------------------------------------
# STEP 2: Download and install the required software packages
# WireGuard is the VPN software that handles all the encrypted
# tunnelling. 'screen' is a helper utility for running sessions.
# ---------------------------------------------------------------
echo "[ 2/10 ] 📦  Downloading and installing WireGuard VPN software..."
echo "         (This requires an internet connection — please wait)"

opkg update && opkg install wireguard-tools screen

echo "         ✔  WireGuard installed successfully!"
echo ""


# ---------------------------------------------------------------
# STEP 3: Define the VPN network settings
# These values describe how the private VPN network is structured.
#   - VPN_IF   : the name for this VPN connection on the router
#   - VPN_PORT : the "door" on the router that VPN traffic enters
#   - VPN_ADDR : the router's IP address inside the VPN network
# ---------------------------------------------------------------
echo "[ 3/10 ] ⚙️   Preparing VPN network settings..."

VPN_IF="wg_homeserver"
VPN_PORT="51820"
VPN_ADDR="192.168.9.1/24"

echo "         VPN interface name : $VPN_IF"
echo "         VPN port           : $VPN_PORT (UDP)"
echo "         VPN server address : $VPN_ADDR"
echo ""


# ---------------------------------------------------------------
# STEP 4: Generate cryptographic keys
# These keys are like unique padlocks — they ensure only YOUR
# device can connect to this VPN, and all traffic is encrypted.
#   - Server key pair : identifies and secures the router
#   - Client key pair : identifies and secures your device
#   - Pre-shared key  : an extra shared secret between both sides
#                       for an additional layer of protection
# Important: Never share private keys with anyone.
# ---------------------------------------------------------------
echo "[ 4/10 ] 🔐  Generating encryption keys for server and client..."
echo "         (These are unique to this setup — never share the private keys)"

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

echo "         ✔  All keys generated and stored securely!"
echo ""


# ---------------------------------------------------------------
# STEP 5a: Configure the firewall
# This tells the router's firewall to allow incoming VPN connections
# on the chosen port, while keeping everything else protected.
# The VPN interface is added to the trusted LAN zone so that
# connected VPN clients get the same access as local devices.
# ---------------------------------------------------------------
echo "[ 5/10 ] 🛡️   Configuring firewall and VPN network interface..."
echo "         (Opening UDP port $VPN_PORT for incoming VPN connections)"

# Add the VPN interface to the trusted LAN zone
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

echo "         ✔  Firewall updated — VPN port $VPN_PORT is now open!"
echo ""


# ---------------------------------------------------------------
# STEP 5b: Configure the VPN network interface on the router
# This creates the actual WireGuard interface on the router and
# registers your client device as an approved, trusted peer.
# The allowed_ips entry restricts this client to its own
# assigned VPN IP address (.2), keeping the network tidy.
# ---------------------------------------------------------------
echo "         Setting up the VPN network interface..."

# Create the WireGuard interface with the server's private key and port
uci -q delete network.${VPN_IF}
uci set network.${VPN_IF}="interface"
uci set network.${VPN_IF}.proto="wireguard"
uci set network.${VPN_IF}.private_key="${VPN_KEY}"
uci set network.${VPN_IF}.listen_port="${VPN_PORT}"
uci add_list network.${VPN_IF}.addresses="${VPN_ADDR}"

# Register the client device as an allowed peer
uci -q delete network.wgclient
uci set network.wgclient="wireguard_${VPN_IF}"
uci set network.wgclient.public_key="${VPN_PUB}"
uci set network.wgclient.preshared_key="${VPN_PSK}"
uci add_list network.wgclient.allowed_ips="${VPN_ADDR%.*}.2/32"

# Save the network configuration
uci commit network
# Note: Uncomment the line below to auto-restart networking (causes a brief disconnect)
# service network restart

echo "         ✔  VPN interface configured and client registered!"
echo ""


# ---------------------------------------------------------------
# STEP 6: Generate the client configuration file
# This is the file you import into the WireGuard app on your
# phone, laptop, or any other device you want to connect with.
# It contains all the information the app needs to find and
# authenticate with your VPN server automatically.
# ---------------------------------------------------------------
echo "[ 6/10 ] 📄  Generating the client config file (wg-client.conf)..."
echo "         (You will import this file into the WireGuard app on your device)"

# Reload key variables from the client's perspective
VPN_KEY="$(cat wgclient.key)"            # Client's private key
VPN_PSK="$(cat wgclient.psk)"            # Pre-shared key
VPN_PUB="$(cat wgserver.pub)"            # Server's public key
CLIENT_ADDRESS="${VPN_ADDR%.*}.2/32"     # Client's assigned VPN IP address
VPNSRV=$(uci get network.lan.ipaddr)     # Router's LAN IP address
SERVER_ENDPOINT="$VPNSRV:$VPN_PORT"     # How the client locates the server
ALLOWED_IPS="0.0.0.0/0, ::/0"           # Route ALL traffic through the VPN
DNS_SERVER="94.140.14.14, 94.140.15.15" # AdGuard DNS (also blocks ads & trackers)

# Write the config file to be imported into the WireGuard app
cat <<EOF > /root/wg-client.conf
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

echo "         ✔  Client config file saved to: /root/wg-client.conf"
echo ""
echo "════════════════════════════════════════════════════════"
echo "  ✅  PART 1 COMPLETE — WireGuard VPN is ready!"
echo "════════════════════════════════════════════════════════"
echo ""
echo "  Here is a summary of your active VPN connections:"
echo ""
wg show
echo ""
echo "────────────────────────────────────────────────────────"
echo "  📋  Your client config (import into the WireGuard app)"
echo "────────────────────────────────────────────────────────"
echo ""
cat /root/wg-client.conf
echo ""
echo "════════════════════════════════════════════════════════"
echo "  PART 2 OF 2 — Network & DNS Configuration"
echo "════════════════════════════════════════════════════════"
echo ""


# ---------------------------------------------------------------
# STEP 7: Disable DNS rebind protection
# By default, the router blocks local domain names that point to
# private IP addresses (a security feature called rebind protection).
# We need to turn this off so that 'my.keepmyhomeip.com' can
# correctly resolve to your router's local IP address instead of
# going out to the internet to look it up.
# ---------------------------------------------------------------
echo "[ 7/10 ] 🔧  Adjusting DNS settings..."
echo "         (Allowing local hostnames to resolve to private IPs)"

uci set dhcp.@dnsmasq[0].rebind_protection='0'
uci commit dhcp
service dnsmasq restart

echo "         ✔  DNS rebind protection disabled and DNS service restarted!"
echo ""


# ---------------------------------------------------------------
# STEP 8: Map the keepmyhomeip domain to the router's local IP
# This adds a static entry to the router's local DNS so that
# 'my.keepmyhomeip.com' points directly to this router (192.168.88.1)
# instead of going out to the internet to look it up.
# Think of it like adding a contact shortcut — dial the name,
# it knows exactly where to go without asking anyone else.
# ---------------------------------------------------------------
echo "[ 8/10 ] 🗺️   Mapping 'my.keepmyhomeip.com' to the router's local IP..."
echo "         (Any device on this network will now resolve it locally)"

echo -e "192.168.88.1\tmy.keepmyhomeip.com" >> /etc/hosts

echo "         ✔  Hostname entry added to /etc/hosts!"
echo ""


# ---------------------------------------------------------------
# STEP 9: Set the router's hostname and local IP address
# - Hostname : a friendly name to identify this router on the network
#              (shows up in dashboards, SSH prompts, logs, etc.)
# - LAN IP   : the address other devices use to reach this router.
#              Changing it from the default (192.168.1.1) avoids
#              IP conflicts if this router sits behind another router.
# ---------------------------------------------------------------
echo "[ 9/10 ] 🌐  Setting the router's name and local IP address..."
echo "         Hostname  : homeServer"
echo "         New IP    : 192.168.88.1  (was likely 192.168.1.1)"

uci set system.@system[0].hostname='homeServer'
uci set network.lan.ipaddr='192.168.88.1'

# Save all changes to disk before reloading services
uci commit network && uci commit system && sync

echo "         ✔  Router name and IP address saved!"
echo ""


# ---------------------------------------------------------------
# STEP 10: Apply network changes by reloading system services
# This restarts the relevant services so the new hostname and IP
# take effect immediately — no full reboot required.
# Note: Your browser or SSH session will need to reconnect
# using the new IP address: 192.168.88.1
# ---------------------------------------------------------------
echo "[ 10/10 ] 🔄  Applying network changes — almost done..."
echo "          ⚠️   After this step, reconnect to the router at:"
echo "               http://192.168.88.1  or  ssh root@192.168.88.1"



echo "          ✔  Network and system reloaded!"
echo ""


# ---------------------------------------------------------------
# ALL DONE — Print full summary
# ---------------------------------------------------------------
echo "════════════════════════════════════════════════════════"
echo "  ✅  SETUP COMPLETE — Everything is ready!"
echo "════════════════════════════════════════════════════════"
echo ""
echo "  Router hostname : homeServer"
echo "  Router LAN IP   : 192.168.88.1"
echo "  Domain mapping  : my.keepmyhomeip.com → 192.168.88.1"
echo "  VPN port        : $VPN_PORT (UDP)"
echo "  VPN server IP   : $VPN_ADDR"
echo ""
echo "────────────────────────────────────────────────────────"
echo "  💡  NEXT STEPS:"
echo "      1. Copy the config above into a file called"
echo "         'wg-client.conf' on your phone or laptop."
echo "      2. Open the WireGuard app and tap"
echo "         'Add tunnel' → 'Import from file'."
echo "      3. Connect — your traffic is now fully encrypted"
echo "         and your home IP travels with you!"
echo "────────────────────────────────────────────────────────"
echo ""

cat /root/wg-client.conf
/etc/init.d/system reload
/etc/init.d/network reload
sync
