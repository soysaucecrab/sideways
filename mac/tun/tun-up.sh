#!/bin/bash
# root로 실행. iproxy(앱이 먼저 띄움) 위에 sing-box tun + DNS 주입 + 워치독.
DIR="$(cd "$(dirname "$0")" && pwd)"
DNSIP="172.19.0.1"
PIDF="/var/run/datasharing-singbox.pid"
WPIDF="/var/run/datasharing-watchdog.pid"
LOG="/var/log/datasharing-tun.log"
SB="/opt/homebrew/bin/sing-box"; [ -x "$SB" ] || SB="/usr/local/bin/sing-box"

echo "[$(date '+%F %T')] tun-up 시작" >> "$LOG"

# 0) 이전 잔여물 정리 (꼬인 상태 복구)
"$DIR/tun-down.sh" >/dev/null 2>&1

# 1) 터널(iproxy) 필요
pgrep -f "iproxy 8888" >/dev/null || { echo "iproxy_not_running"; echo "[$(date '+%T')] iproxy 없음" >> "$LOG"; exit 2; }

# 2) 충돌하는 시스템 SOCKS 프록시 끄기
for svc in $(networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | grep -v '^\*'); do
  networksetup -setsocksfirewallproxystate "$svc" off 2>/dev/null || true
done

# 3) sing-box 백그라운드
nohup "$SB" run -c "$DIR/config.json" >>"$LOG" 2>&1 &
echo $! > "$PIDF"; disown 2>/dev/null || true
sleep 3

UTUN=$(ifconfig 2>/dev/null | awk '/^utun[0-9]/{i=$1} /172\.19\.0\.1/{print i}' | tr -d ':' | head -1)
[ -n "$UTUN" ] || { echo "utun_not_found"; echo "[$(date '+%T')] utun 없음" >> "$LOG"; "$DIR/tun-down.sh" >/dev/null 2>&1; exit 3; }

# 4) DNS 주입 (Wi-Fi 없어도 모든 앱이 해석되도록)
scutil >/dev/null 2>&1 <<SC
open
d.init
d.add ServerAddresses * $DNSIP
d.add SupplementalMatchDomains * ""
set State:/Network/Service/singboxdns/DNS
d.init
d.add Addresses * $DNSIP
d.add SubnetMasks * 255.255.255.252
d.add Router $DNSIP
d.add InterfaceName $UTUN
set State:/Network/Service/singboxdns/IPv4
close
SC
dscacheutil -flushcache 2>/dev/null || true
killall -HUP mDNSResponder 2>/dev/null || true

# 5) 워치독: iproxy(=앱)가 죽으면 자동 정리 (강제종료/크래시 대비)
nohup bash -c '
  while pgrep -f "iproxy 8888" >/dev/null 2>&1; do sleep 2; done
  rm -f '"$WPIDF"'
  '"$DIR"'/tun-down.sh >/dev/null 2>&1
' >/dev/null 2>&1 &
echo $! > "$WPIDF"; disown 2>/dev/null || true

echo "[$(date '+%T')] tun-up 완료(ok)" >> "$LOG"
echo "ok"
