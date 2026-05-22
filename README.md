# Jarvis iOS App

자비스 음성 대화 앱 (SwiftUI, iOS 16+)

## 구조

| 파일 | 역할 |
|------|------|
| `JarvisApp.swift` | 앱 진입점 |
| `ContentView.swift` | UI (다크 테마, 마이크 버튼, 대화창) |
| `VoiceManager.swift` | 음성 인식 + API 호출 + MP3 재생 |
| `JarvisAPI.swift` | HTTP 클라이언트 (`/api/chat`, `/api/clear`, `/api/health`) |
| `Info.plist` | 권한 선언 + HTTP ATS 예외 설정 |

## Xcode 프로젝트 생성 방법

1. **Xcode 열기** → File → New → Project
2. **iOS → App** 선택 후 Next
   - Product Name: `JarvisApp`
   - Interface: **SwiftUI**
   - Language: **Swift**
3. 저장 위치 선택 후 Create

4. **기존 파일 교체**
   - Xcode가 생성한 `ContentView.swift`, `JarvisApp.swift` 삭제
   - 이 폴더의 `.swift` 4개 파일을 프로젝트로 드래그

5. **Info.plist 설정** (두 가지 방법 중 하나)

   **방법 A - 직접 편집 (권장)**
   - Project Navigator에서 `Info.plist` 선택
   - 우클릭 → Open As → Source Code
   - 이 폴더의 `Info.plist` 내용으로 교체

   **방법 B - Xcode UI에서 추가**
   - Target → Info 탭에서 아래 키 추가:
     - `NSMicrophoneUsageDescription` = "자비스와 음성으로 대화하기 위해 마이크가 필요합니다."
     - `NSSpeechRecognitionUsageDescription` = "자비스와 음성으로 대화하기 위해 음성 인식이 필요합니다."
   - Target → Info → URL Types 아래 `App Transport Security Settings` 추가:
     - Exception Domains → `devon.gonetis.com` → Allow Arbitrary Loads in Web Content: YES

6. **Deployment Target 설정**
   - Target → General → Minimum Deployments → **iOS 16.0**

7. **실기기에 설치**
   - iPhone을 Mac에 연결
   - Xcode 상단 Device 선택 → Run (⌘R)
   - 처음 실행 시: Settings → General → VPN & Device Management → 개발자 인증서 신뢰

## 사용법

| 상태 | 설명 |
|------|------|
| 파란 마이크 | 탭하면 듣기 시작 |
| 빨간 정지 (깜빡임) | 말하는 중 — 다시 탭하면 즉시 전송, 또는 말 멈추면 자동 전송 |
| 주황 | 서버 처리 중 |
| 초록 | 자비스 음성 응답 중 |

- 우측 상단 휴지통: 대화 세션 초기화
- 연결 상태 (녹색/빨간 점): 서버 연결 여부

## 주의사항

- 현재 서버(`devon.gonetis.com:8767`)가 HTTP이므로 HTTPS 전환 시 `Info.plist`의 ATS 예외 제거 필요
- 실기기 설치에는 Apple Developer 계정 필요 (무료 계정도 가능, 7일 유효)
- 시뮬레이터에서는 마이크/음성인식 미동작 — 반드시 실기기 테스트 필요
