#!/bin/bash
# 최초 1회(또는 업데이트 시)만 root로 실행. 무암호 실행 권한(sudoers) + root 소유 스크립트 설치.
# $1 = 스크립트 원본 디렉토리 (앱 Resources 경로). $2 = 버전 문자열.
SRC="$1"
VER="$2"
DEST="/usr/local/libexec/datasharing"
[ -d "$SRC" ] && [ -f "$SRC/tun-up.sh" ] || { echo "src_missing"; exit 1; }
mkdir -p "$DEST"
cp "$SRC/tun-up.sh" "$SRC/tun-down.sh" "$SRC/config.json" "$DEST/" || { echo "copy_failed"; exit 1; }
chown -R root:wheel "$DEST"
chmod 755 "$DEST"/*.sh
chmod 644 "$DEST/config.json"
SUDOF="/etc/sudoers.d/datasharing"
printf '%%admin ALL=(root) NOPASSWD: %s/tun-up.sh, %s/tun-down.sh\n' "$DEST" "$DEST" > "$SUDOF"
chmod 440 "$SUDOF"
if visudo -cf "$SUDOF" >/dev/null 2>&1; then
  echo "$VER" > "$DEST/.version"
  echo "ok"
else
  rm -f "$SUDOF"
  echo "sudoers_invalid"
  exit 1
fi
