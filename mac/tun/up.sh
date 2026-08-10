#!/bin/bash
# 모든 앱을 iPhone 인터넷(USB 터널)으로. Wi-Fi 없이도 작동. root로 실행.
# 전제: Mac 헬퍼 앱에서 '시작'(iproxy 127.0.0.1:8888)이 떠 있어야 함.
DIR="$(cd "$(dirname "$0")" && pwd)"
DNSIP="172.19.0.1"

if ! pgrep -f "iproxy 8888" >/dev/null; then
  echo "❌ iproxy가 안 떠 있습니다. 먼저 Mac 헬퍼 앱에서 '시작'을 누르세요."
  exit 1
fi

cleanup() {
  echo ""; echo "정리: DNS 원복 + sing-box 종료..."
  scutil >/dev/null 2>&1 <<SC
open
remove State:/Network/Service/singboxdns/DNS
remove State:/Network/Service/singboxdns/IPv4
close
SC
  dscacheutil -flushcache 2>/dev/null
  killall -HUP mDNSResponder 2>/dev/null
  kill "$SB" 2>/dev/null; wait "$SB" 2>/dev/null
}
trap cleanup EXIT INT TERM

echo "▶ TUN 터널 시작 중..."
/opt/homebrew/bin/sing-box run -c "$DIR/config.json" &
SB=$!
sleep 3

UTUN=$(ifconfig 2>/dev/null | awk '/^utun[0-9]/{i=$1} /172\.19\.0\.1/{print i}' | tr -d ':' | head -1)
[ -z "$UTUN" ] && { echo "❌ utun 없음 (sing-box 시작 실패?)"; exit 1; }

# DNS를 sing-box로 주입 (Wi-Fi 없어도 모든 앱이 해석)
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
dscacheutil -flushcache 2>/dev/null
killall -HUP mDNSResponder 2>/dev/null

echo "✅ 완료! Wi-Fi 없이도 모든 앱이 iPhone 인터넷으로 나갑니다."
echo "   중지: Ctrl-C (DNS 자동 복구)"
wait "$SB"
