#!/bin/bash
# root로 실행. iproxy(앱이 먼저 띄움) 위에 sing-box tun + DNS 주입.
DIR="$(cd "$(dirname "$0")" && pwd)"
DNSIP="172.19.0.1"
PIDF="/var/run/datasharing-singbox.pid"
SB="/opt/homebrew/bin/sing-box"; [ -x "$SB" ] || SB="/usr/local/bin/sing-box"

# 이미 실행중이면 스킵
if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null; then echo "already_running"; exit 0; fi
# iproxy(터널) 필요
pgrep -f "iproxy 8888" >/dev/null || { echo "iproxy_not_running"; exit 2; }

# tun과 충돌하는 시스템 SOCKS 프록시 끄기
for svc in $(networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | grep -v '^\*'); do
  networksetup -setsocksfirewallproxystate "$svc" off 2>/dev/null || true
done

# sing-box 백그라운드
nohup "$SB" run -c "$DIR/config.json" >/dev/null 2>&1 &
echo $! > "$PIDF"; disown 2>/dev/null || true
sleep 3

UTUN=$(ifconfig 2>/dev/null | awk '/^utun[0-9]/{i=$1} /172\.19\.0\.1/{print i}' | tr -d ':' | head -1)
[ -n "$UTUN" ] || { echo "utun_not_found"; exit 3; }

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
echo "ok"
