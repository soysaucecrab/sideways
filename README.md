# Data Sharing — iPhone 셀룰러를 USB로 Mac과 공유

iPhone의 셀룰러 데이터를 USB로 연결된 Mac에 SOCKS5 프록시로 공유합니다.
캐리어 테더링(개인용 핫스팟) 없이, 트래픽은 iPhone의 일반 트래픽으로 나갑니다.

자세한 설계는 [`spec.md`](spec.md), 작업 규칙은 [`CLAUDE.md`](CLAUDE.md) 참고.

## 구성

```
Mac 앱 → 127.0.0.1:8888 (Mac) --USB/usbmuxd--> iPhone:8888 (SOCKS5) → 셀룰러 → 인터넷
```

- **`ios/`** — iPhone SOCKS5 프록시 앱 (Swift / Network.framework)
  - `127.0.0.1:8888`에서 SOCKS5 `CONNECT` 수신, 원격 DNS(도메인 주소 타입) 지원
  - 아웃바운드는 셀룰러 인터페이스로 고정(`requiredInterfaceType = .cellular`)
  - 포그라운드 UI: 시작/중지, 활성 연결 수, 송·수신 바이트, 리슨 포트
- **`mac/`** — macOS 메뉴바 헬퍼 앱 (SwiftUI `MenuBarExtra`)
  - `iproxy`(libimobiledevice)를 실행해 Mac 로컬 포트 ↔ iPhone 포트 USB 브리지
  - 시스템 SOCKS 프록시를 `networksetup`으로 켜고/끔
  - 연결된 iPhone UDID/이름 자동 감지

## 사전 요구사항

- macOS 14+, Xcode 26
- `brew install libimobiledevice xcodegen`
- iOS 17+ 기기, USB 연결 + 신뢰(trust) + 잠금 해제

## 빌드

### iPhone 앱
```sh
cd ios
xcodegen generate
open DataSharing.xcodeproj   # 기기 선택 후 실행 (무료 Apple ID는 7일마다 재서명)
```

### macOS 앱
```sh
cd mac
xcodegen generate
open DataSharingMac.xcodeproj # 실행하면 메뉴바에 안테나 아이콘
```
> macOS 앱은 `iproxy` 실행과 `networksetup` 호출을 위해 **비샌드박스**로 서명됩니다.
> 프록시 설정 변경에는 관리자 권한이 필요할 수 있습니다.

## 사용 순서

1. iPhone 앱을 열고 **시작** — SOCKS5 리스너가 뜹니다(화면 켜둔 채 포그라운드 유지).
2. iPhone을 USB로 Mac에 연결(신뢰/잠금 해제).
3. macOS 메뉴바 앱에서 네트워크 서비스·포트 확인 후 **시작**.
   - `iproxy`가 뜨고, 시스템 SOCKS 프록시가 `127.0.0.1:<포트>`로 설정됩니다.
4. 브라우저 등에서 페이지가 셀룰러를 통해 열리는지 확인.
5. 끝나면 macOS 앱에서 **중지** — 프록시 설정이 자동 해제됩니다.

## 현재 범위 (M1~M3)

구현됨: SOCKS5 `CONNECT`(IPv4/IPv6/도메인), 원격 DNS, 양방향 릴레이, 동시 연결,
셀룰러 핀닝, iPhone 통계 UI, macOS `iproxy`+프록시 토글, UDID 자동 감지.

미구현(spec §7, M4): UDP `associate`, iOS 백그라운드 지속 실행, 자동 재연결.

## 라이선스

[Apache License 2.0](LICENSE)
