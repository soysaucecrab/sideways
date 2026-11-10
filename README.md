# Data Sharing — iPhone 셀룰러를 USB로 Mac과 공유

iPhone의 셀룰러 데이터를 USB로 연결된 Mac에 SOCKS5 프록시로 공유합니다.
캐리어 테더링(개인용 핫스팟) 없이, 트래픽은 iPhone의 일반 트래픽으로 나갑니다.

자세한 설계는 [`spec.md`](spec.md) 참고.

## 구성

```
Mac 모든 앱 → TUN(sing-box) → 127.0.0.1:8888 (Mac) --USB/usbmuxd--> iPhone:8888 (SOCKS5) → 셀룰러 → 인터넷
```

- **`ios/`** — iPhone SOCKS5 프록시 앱 (Swift / Network.framework)
  - SOCKS 서버는 **VPN 확장(Packet Tunnel)** 안에서 돌아서, 앱을 나가거나 화면을 꺼도 계속 동작합니다.
    실행 중에는 상단에 VPN 표시가 나타납니다. VPN 경로로는 아무 트래픽도 보내지 않아 iPhone 자체 인터넷에는 영향이 없습니다.
  - `127.0.0.1:8888`에서 SOCKS5 `CONNECT` 수신, 원격 DNS(도메인 주소 타입) 지원
  - **셀룰러 강제** 옵션을 켜면 아웃바운드를 셀룰러로 고정(`requiredInterfaceType = .cellular`)
  - UI: 시작/중지, 현재 속도, 활성 연결 수, 송·수신 바이트, 일·월·전체 누적 사용량
  - 제어 센터 토글(iOS 18+): 제어 센터 편집 → **Data Sharing** 컨트롤 추가.
    토글을 누르면 앱이 열리면서 VPN을 켜고 끄며, 그 뒤 앱은 닫아도 됩니다.
- **`mac/`** — macOS 메뉴바 앱 (SwiftUI `MenuBarExtra`)
  - **시작** 한 번으로 `iproxy`(USB 브리지, Mac 내부 `127.0.0.1`에만 열림)와
    `sing-box` TUN을 띄워 **Mac의 모든 앱**을 iPhone으로 보냅니다(Wi‑Fi 불필요).
  - TUN·DNS 설정은 root 권한이 필요해 최초 1회 관리자 인증으로 헬퍼 스크립트를 설치합니다.
  - USB 연결(`iproxy`)이 끊기면 watchdog이 TUN·DNS 설정을 자동으로 정리하고,
    앱이 비정상 종료된 경우 다음 실행 때 남은 설정을 정리합니다.

## 사전 요구사항

- macOS 14+, Xcode 27
- `brew install libimobiledevice xcodegen sing-box`
- iOS 17+ 기기, USB 연결 + 신뢰(trust) + 잠금 해제, **개발자 모드** 켜짐
- **유료 Apple Developer 계정** — VPN 확장(Network Extension) 권한은 무료 계정으로 받을 수 없습니다.

## 빌드 · 설치

### iPhone 앱
Xcode 설정 → Accounts에 개발자 계정이 로그인되어 있어야 합니다. 팀 ID는 `ios/project.yml`의
`DEVELOPMENT_TEAM`에 지정되어 있습니다.

```sh
cd ios
xcodegen generate
# iPhone을 USB로 연결하고 잠금 해제한 상태에서
xcodebuild -project DataSharing.xcodeproj -scheme DataSharing -configuration Release \
  -destination 'id=<iPhone UDID>' -derivedDataPath build/dd-signed -allowProvisioningUpdates build
xcrun devicectl device install app --device <iPhone UDID> \
  build/dd-signed/Build/Products/Release-iphoneos/DataSharing.app
```

- UDID 확인: `xcrun devicectl list devices`
- 개발 서명은 **1년** 유효합니다. 만료일은 앱의 **서명** 항목에 표시되며, 만료 전 위 명령으로 다시 설치하면 됩니다.
- 처음 App Group을 등록할 때는 Xcode에서 프로젝트를 열고 각 타깃의 **Signing & Capabilities**를
  한 번 확인해야 할 수 있습니다(`xcodebuild`는 새 App Group을 계정에 등록하지 않음).

### macOS 앱
```sh
cd mac
xcodegen generate
xcodebuild -project DataSharingMac.xcodeproj -scheme DataSharingMac -configuration Release \
  -derivedDataPath build/dd CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" build
cp -R build/dd/Build/Products/Release/DataSharingMac.app /Applications/
```
> macOS 앱은 `iproxy` 실행과 TUN 헬퍼 호출을 위해 **비샌드박스**로 서명됩니다.

## 사용 순서

1. iPhone을 USB로 Mac에 연결(신뢰/잠금 해제).
2. iPhone 앱을 열고 **시작** — 처음 한 번은 VPN 구성 추가를 **허용**합니다. 이후 앱은 닫아도 됩니다.
3. macOS 메뉴바 앱에서 **시작** — 처음 한 번은 관리자 인증을 요구합니다.
4. 브라우저 등에서 페이지가 iPhone을 통해 열리는지 확인.
5. 끝나면 macOS 앱에서 **중지**, iPhone 앱에서 **중지**(또는 제어 센터 토글).

## 현재 범위

구현됨: SOCKS5 `CONNECT`(IPv4/IPv6/도메인), 원격 DNS, 양방향 릴레이, 동시 연결,
셀룰러 핀닝, iOS 백그라운드 지속 실행(VPN 확장), 통계·누적 사용량 UI,
macOS 원클릭 TUN(모든 앱), UDID 자동 감지, 제어 센터 토글(iOS 18+).

미구현(spec §7, M4): UDP `associate`, 자동 재연결.

## 라이선스

[Apache License 2.0](LICENSE)
