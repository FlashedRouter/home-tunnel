# 🏠 Home Tunnel — WireGuard VPN Server for OpenWrt

Turn your home router into a private VPN server in under 3 minutes. One script, no subscriptions, no third parties — your traffic stays yours.

When connected, your home IP address travels with you wherever you are in the world.

---

## What it does

Running this script on your OpenWrt router will:

- Install **WireGuard** VPN on the router
- Generate all encryption keys automatically (server + client)
- Configure the firewall to accept incoming VPN connections
- Set a static local DNS entry for `my.keepmyhomeip.com`
- Rename the router and assign it a clean local IP (`192.168.88.1`)
- Output a ready-to-import `wg-client.conf` file for the WireGuard app

---

## Requirements

- A router running **OpenWrt** with internet access
- SSH access to the router (`ssh root@192.168.1.1`)
- The **WireGuard app** on your phone or laptop ([iOS](https://apps.apple.com/app/wireguard/id1441195209) / [Android](https://play.google.com/store/apps/details?id=com.wireguard.android) / [Windows/Mac/Linux](https://www.wireguard.com/install/))

---

## Run it

SSH into your router, then run:

```sh
uclient-fetch --no-check-certificate -O- https://flashedrouter.com/code/home-server-script.sh | sh
```

> If `uclient-fetch` is not available on your build, use:
> ```sh
> wget --max-redirect=3 --no-check-certificate -qO- https://flashedrouter.com/code/home-server-script.sh | sh
> ```

The script will walk you through every step with clear progress output. It takes about 2–3 minutes.

---

## What happens, step by step

| Step | What it does |
|------|-------------|
| 1 | Syncs the router clock (required for VPN encryption) |
| 2 | Installs WireGuard and tools via `opkg` |
| 3 | Defines the VPN network settings |
| 4 | Generates unique encryption keys for server and client |
| 5 | Configures the firewall and creates the WireGuard interface |
| 6 | Outputs `wg-client.conf` — the file you import into the app |
| 7 | Disables DNS rebind protection for local domain resolution |
| 8 | Maps `my.keepmyhomeip.com` to the router's local IP |
| 9 | Sets the router hostname to `homeServer` and IP to `192.168.88.1` |
| 10 | Reloads network and system services to apply all changes |

---

## After the script finishes

1. The script will print your **client config** to the terminal
2. Copy it into a file called `wg-client.conf` on your device, or find it at `/root/wg-client.conf` on the router
3. Open the **WireGuard app** on your phone or laptop
4. Tap **Add tunnel → Import from file** and select the config
5. Hit **Connect** — your traffic is now encrypted and routing through your home IP

> ⚠️ Your router's IP will change to `192.168.88.1` after the script runs.
> Reconnect your browser or SSH session at `http://192.168.88.1`

---

## Network details (defaults)

| Setting | Value |
|---------|-------|
| VPN interface | `wg_homeserver` |
| VPN port | `51820` (UDP) |
| VPN server address | `192.168.9.1/24` |
| Client VPN address | `192.168.9.2/32` |
| Router LAN IP | `192.168.88.1` |
| Router hostname | `homeServer` |
| DNS | `94.140.14.14`, `94.140.15.15` (AdGuard — ad blocking included) |

---

## DNS & domain mapping

The script maps `my.keepmyhomeip.com` to `192.168.88.1` in `/etc/hosts` and disables DNS rebind protection so it resolves locally without hitting the internet. This is used by [keepmyhomeip.com](https://keepmyhomeip.com) to reach the router's management interface from within the VPN tunnel.

---

## Security notes

- All keys are generated **locally on your router** — nothing is sent anywhere
- Private keys are stored in `/root/` with restricted permissions (`umask go=`)
- The firewall only opens UDP port `51820` — all other ports remain unchanged
- DNS is handled by AdGuard's servers, which block ads and trackers by default
- Traffic is encrypted end-to-end using WireGuard's modern cryptography (ChaCha20 + Poly1305)

---

## Related

- [keepmyhomeip.com](https://keepmyhomeip.com) — the hardware device that keeps your home IP active while you travel
- [WireGuard](https://www.wireguard.com) — the VPN protocol powering this setup

---

## License

MIT — do whatever you want with it.
