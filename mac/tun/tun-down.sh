#!/bin/bash
# root로 실행. tun + DNS 주입 해제.
PIDF="/var/run/datasharing-singbox.pid"
WPIDF="/var/run/datasharing-watchdog.pid"
# 워치독 먼저 종료 (중복 정리 방지)
if [ -f "$WPIDF" ]; then kill "$(cat "$WPIDF")" 2>/dev/null; rm -f "$WPIDF"; fi
# DNS 복구
scutil >/dev/null 2>&1 <<SC
open
remove State:/Network/Service/singboxdns/DNS
remove State:/Network/Service/singboxdns/IPv4
close
SC
dscacheutil -flushcache 2>/dev/null || true
killall -HUP mDNSResponder 2>/dev/null || true
# sing-box 종료
if [ -f "$PIDF" ]; then kill "$(cat "$PIDF")" 2>/dev/null; rm -f "$PIDF"; fi
pkill -f "sing-box run" 2>/dev/null || true
echo "ok"
