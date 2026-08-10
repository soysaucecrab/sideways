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
  - 제어 센터 토글(iOS 18+): 제어 센터 편집 → **Data Sharing** 컨트롤 추가.
    프록시는 포그라운드 전용이므로 토글을 켜면 앱이 열리면서 시작됩니다.
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

## AltStore로 설치 (7일 재서명 자동화)

무료 Apple ID로 사이드로드하면 개발 서명이 **7일마다 만료**됩니다.
[AltStore](https://altstore.io)를 쓰면 Mac의 AltServer가 만료 전에 **자동으로 재서명·재설치**해 줍니다.
이 앱은 어차피 Mac에 USB로 물려서 쓰므로, "갱신 시 Mac이 근처에 있어야 한다"는 AltStore의 제약이 문제되지 않습니다.

> EU 전용 **AltStore PAL**이 아니라, **AltServer 기반 클래식 AltStore**를 사용하세요.

### 1. `.ipa` 만들기

서명 없이 아카이브한 뒤 `Payload/`로 감싸 `.ipa`로 압축합니다(서명은 AltStore가 설치 시 처리).

```sh
cd ios
xcodegen generate

# 서명 없이 기기용(iphoneos) .app 빌드
xcodebuild -project DataSharing.xcodeproj -target DataSharing \
  -sdk iphoneos -configuration Release ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

# .app 을 Payload/ 로 감싸 .ipa 로 압축 (서명은 AltStore가 설치 시 처리)
cd build
rm -rf Payload DataSharing.ipa
mkdir Payload
cp -R Release-iphoneos/DataSharing.app Payload/
zip -qry DataSharing.ipa Payload
echo "생성됨: ios/build/DataSharing.ipa"
```

### 2. AltServer 설치 (Mac, 최초 1회)

1. <https://altstore.io> 에서 **AltServer**를 내려받아 `/Applications`에 설치.
2. AltServer 실행 → 메뉴바 아이콘 생성.
3. iPhone을 USB로 연결하고 **신뢰(Trust)** 후 잠금 해제.
4. 메뉴바 AltServer → **Install AltStore → (내 기기)** 선택.
   - Apple ID 로그인 요청 시 입력(앱 암호가 아니라 실제 Apple ID). 2단계 인증이면 앱 암호를 요구할 수 있습니다.
5. iPhone에 AltStore 앱이 설치됨. **설정 → 일반 → VPN 및 기기 관리**에서 본인 Apple ID 개발자 앱을 **신뢰**.

### 3. 이 앱 설치

1. 만든 `DataSharing.ipa`를 iPhone에서 접근 가능한 위치(예: AirDrop, 파일 앱)로 옮기거나 USB 연결 유지.
2. iPhone의 **AltStore → My Apps → 좌상단 `+`** → `DataSharing.ipa` 선택.
3. Apple ID 재확인 후 설치 완료.

> 앱에 제어 센터 위젯 확장이 포함되어 있어 App ID를 2개(앱+확장) 사용합니다.
> 설치 중 확장(extension)을 유지할지 물으면 **Keep**을 선택하세요(제어 센터 토글에 필요).

### 4. 자동 갱신 유지

- iPhone AltStore의 **My Apps**에 남은 만료일이 표시됩니다.
- **AltServer가 켜진 Mac과 같은 Wi‑Fi**에 있으면 만료 전 백그라운드로 자동 갱신됩니다.
- 수동 갱신: My Apps → **Refresh All**. (앱 데이터는 유지됩니다.)
- 무료 계정 제약: 활성 사이드로드 앱 3개/기기, App ID 갱신 주간 한도 등이 그대로 적용됩니다.

## 현재 범위 (M1~M3)

구현됨: SOCKS5 `CONNECT`(IPv4/IPv6/도메인), 원격 DNS, 양방향 릴레이, 동시 연결,
셀룰러 핀닝, iPhone 통계 UI, macOS `iproxy`+프록시 토글, UDID 자동 감지,
제어 센터 토글(iOS 18+, 켜기는 앱 열림 방식).

미구현(spec §7, M4): UDP `associate`, iOS 백그라운드 지속 실행, 자동 재연결.

## 라이선스

[Apache License 2.0](LICENSE)
