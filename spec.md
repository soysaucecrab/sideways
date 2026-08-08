# spec.md — iPhone-to-macOS Data Sharing Proxy

## 1. Overview
- Share the iPhone's cellular data connection with a USB-connected Mac.
- No carrier tethering / Personal Hotspot required.
- Traffic leaves the network as ordinary iPhone traffic (carrier sees only the phone).
- Personal tool, sideloaded — not App Store distributed.

## 2. Goals
- Route arbitrary TCP traffic from the Mac out through the iPhone's cellular link.
- Resolve DNS on the iPhone side (remote DNS) so the Mac needs no other network.
- Zero-config on the Mac beyond one proxy setting + one helper command.

## 3. Non-Goals
- Not a general VPN; no system-wide packet tunneling on iOS (v1).
- No 24/7 background operation on iPhone (v1 = foreground session only).
- No multi-device / hotspot-style broadcast; single Mac over USB only.

## 4. Architecture
Three cooperating parts:
- **iPhone app** — SOCKS5 proxy server listening on a local port.
- **USB tunnel** — `usbmuxd` + `iproxy` forwarding a Mac local port to the iPhone port.
- **macOS config** — system SOCKS proxy pointed at the forwarded local port.

```
Mac app → 127.0.0.1:8888 (Mac) --USB/usbmuxd--> iPhone:8888 (SOCKS5) → cellular → internet
```

## 5. Components

### 5.1 iPhone App (Swift)
- SOCKS5 proxy server built on `Network.framework` (`NWListener`, `NWConnection`).
- Listen on `127.0.0.1:<port>` (default 8888).
- Support SOCKS5 `CONNECT`; remote DNS resolution (address type = domain name).
- Per-connection relay: read from Mac side, open outbound `NWConnection` over cellular, pipe both directions.
- Foreground UI: start/stop toggle, active-connection count, bytes in/out, listen port.
- Force outbound path over cellular where possible (`NWParameters.requiredInterfaceType = .cellular`).

### 5.2 USB Tunnel (Mac side)
- Dependency: `libimobiledevice` (`brew install libimobiledevice`).
- Command: `iproxy <mac_port> <iphone_port> [-u <udid>]`.
- Requires the iPhone to be unlocked and trusted.
- Wrap in a small launch script that starts `iproxy` and prints status.

### 5.3 macOS Configuration
- Set SOCKS proxy to `127.0.0.1:<mac_port>` (System Settings → Network → Proxies, or `networksetup -setsocksfirewallproxy`).
- Enable "use proxy for DNS" so lookups go remote.
- Provide script to toggle the proxy on/off cleanly.

## 6. Data Flow
1. iPhone app starts SOCKS5 listener.
2. `iproxy` bridges Mac local port ↔ iPhone port over USB.
3. Mac app connects to local SOCKS proxy.
4. iPhone app opens the outbound connection over cellular and relays bytes.

## 7. Constraints & Known Limitations
- **Foreground only (v1):** iOS suspends backgrounded apps; keep the app open with screen on. Background persistence (silent-audio session, etc.) deferred to later phase.
- **Signing:** free Apple ID cert expires every 7 days (re-sign needed); paid account = 1 year.
- **UDP:** SOCKS5 UDP-associate not in v1; TCP + remote DNS only.
- **Carrier policy:** bypassing tethering limits may violate carrier ToS (not illegal, but a contractual matter).

## 8. Milestones
- **M1:** Minimal SOCKS5 CONNECT relay + manual `iproxy` + manual Mac proxy setting; verify a browser page loads.
- **M2:** iPhone app UI (start/stop, live stats), cellular-interface pinning.
- **M3:** Mac launch script (auto `iproxy` + proxy toggle), UDID auto-detect.
- **M4:** Background-persistence experiment; reconnection handling.

## 9. Open Questions
- Preferred listen port / configurability.
- Whether to add a Mac-side menu-bar helper vs. plain shell scripts.
- Target minimum iOS version.
