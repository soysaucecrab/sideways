#!/bin/bash
# root로 실행. sing-box tun + DNS 주입 해제.
PIDF="/var/run/datasharing-singbox.pid"
scutil >/dev/null 2>&1 <<SC
open
remove State:/Network/Service/singboxdns/DNS
remove State:/Network/Service/singboxdns/IPv4
close
SC
dscacheutil -flushcache 2>/dev/null || true
killall -HUP mDNSResponder 2>/dev/null || true
if [ -f "$PIDF" ]; then kill "$(cat "$PIDF")" 2>/dev/null; rm -f "$PIDF"; fi
pkill -f "sing-box run" 2>/dev/null || true
echo "ok"
