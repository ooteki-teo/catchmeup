# CatchMeUp

> macOS 네이티브 개인 작업 도우미. 스크린샷·텍스트·파일·폴더·URL을 넣으면 항목과 할 일로 정리하고, "어디까지 했고 다음에 뭘 할지"를 기억해 줍니다.

[简体中文](README.md) · [English](README.en.md) · [Español](README.es.md) · [日本語](README.ja.md) · **한국어**

CatchMeUp은 **단일 파일 네이티브 macOS 앱**(SwiftUI + Swift 6)입니다. Electron도 Python도 필요 없으며, DeepSeek API 호출 외에는 모두 로컬에서 실행됩니다.

---

## 기능

### 통합 캡처 (WeChat 스타일, 최소 클릭)
- 입력창 하나로 전부 해결: **텍스트 / URL / 파일 경로 / 파일 드래그 / 폴더 드래그 / 스크린샷 붙여넣기(⌘V) / 영역 선택** — 종류를 자동 인식합니다.
- 스마트 라우팅: URL은 본문 수집, 경로는 파일 읽기, 이미지는 OCR 또는 비전 모델로.
- 전역 단축키(기본 `⌘⇧M`, **변경 가능**): 어디서든 영역 선택 → 앱이 앞으로 나와 분석합니다.

### AI 정리 (DeepSeek)
- 기본 모델 `deepseek-flash`(이미지 지원). `deepseek-v4-pro`로 전환 가능.
- 제목·요약·태그·분류와 함께 두 가지 구조화 결과 생성:
  - **작업**: 명확한 마감이 있는 할 일;
  - **인수인계**: 프로젝트 정리(목표 / 접근 / 상세 진행 / 다음 단계 / 위험).
- 스크린샷은 먼저 비전 모델, 실패 시 내장 **Vision OCR**(중국어+영어)로 대체.
- 폴더는 "README(있으면) + 디렉터리 트리 + 파일별 한 줄 설명"으로 요약하며 전문을 붙여넣지 않습니다.

### 작업 시스템 (날짜별 그룹, 원클릭)
- 기본 "작업" 보기는 **지남 / 오늘 / 내일 / 이번 주 / 나중에 / 날짜 없음 / 완료**로 그룹화.
- 한 줄 입력 후 Return으로 생성. 동그라미로 완료, 날짜를 눌러 일정 변경, 점으로 우선순위 변경.
- 정시 로컬 알림(앱을 꺼도 표시), 매일/매주/매월 반복 지원.
- 마감이 있는 작업을 **시스템 캘린더**에 기록하는 옵션.

### 인수인계 (연속 추적)
- 각 인수인계 항목에 "증분 업데이트": 원본을 다시 읽고 이전 인수인계를 넘겨, 유효한 진행은 유지하고 변경만 추가합니다.
- 세션 시작/종료와 Markdown으로 복사 가능한 인수인계 요약 생성.

### 그 외
- 메뉴 막대: 빠른 메모, 스크린샷, 클립보드, 다가오는 작업.
- **토큰 사용량 통계**(설정 → DeepSeek): 호출/입력/출력/합계, 모델별.
- API 키는 로컬 파일에 저장(키체인 미사용) — **권한 창이 뜨지 않습니다**.
- 모든 권한(알림/캘린더/화면 기록)은 **설정에서 버튼을 눌렀을 때만** 요청합니다. 실행 시에는 아무것도 뜨지 않습니다.
- **지원 언어: 简体中文 / English / Español / 日本語 / 한국어** (설정 → 언어; 시스템 따르기 또는 선택).

---

## 요구 사항

- macOS 14.0 이상 (Apple Silicon 검증됨)
- Xcode 또는 Command Line Tools (Swift 6)
- [DeepSeek](https://platform.deepseek.com/) API 키
- 선택: Apple Development 인증서(재빌드 후에도 권한 유지, 아래 참고)

---

## 빠른 시작

```bash
bash scripts/build.sh      # 빌드 후 dist/CatchMeUp.app 생성
open "dist/CatchMeUp.app"
bash scripts/test.sh       # 또는 swift test
```

첫 실행:

1. **설정 → DeepSeek**에서 API 키를 붙여넣고 **저장**.
2. **설정 → 권한**에서 필요한 항목 허용(알림, 캘린더, 화면 기록).
3. `⌘⇧M`(**설정 → 일반**에서 변경 가능)으로 영역을 선택해 자동 분석.

---

## 사용법

| 상황 | 동작 |
| --- | --- |
| 텍스트 기록 | 워크스페이스 입력창에 입력 후 Return |
| 웹 페이지 저장 | URL 붙여넣고 Return |
| 프로젝트 폴더 정리 | 폴더를 드래그(인수인계로 처리) |
| 스크린샷 정리 | `⌘⇧M`, 카메라 버튼, 또는 ⌘V 붙여넣기 |
| 항목 보기 | 카드 클릭 → 별도 창(이동/크기조절 가능, **새로고침** 제공) |
| 작업 | 작업 탭에서 한 줄 입력; 마감/우선순위/완료를 인라인으로 |
| 인수인계 | 인수인계 탭에서 생성 또는 카드에서 업데이트 |

---

## 구조

```text
catchmeup/
├── Package.swift                 # SwiftPM (macOS 14+, 외부 의존성 없음)
├── Sources/
│   ├── CatchMeUpCore/            # 모델·저장·AI·OCR·캘린더·알림
│   │   └── L10n.swift            # 현지화 (zh/en/es/ja/ko)
│   └── CatchMeUpApp/             # SwiftUI 계층
├── Tests/CatchMeUpCoreTests/
└── scripts/
```

---

## 데이터 및 개인정보

- 데이터 폴더: `~/Library/Application Support/CatchMeUp/` (`catchmeup.db`, `storage/`, `secrets.json`, `usage.json`).
- API 키는 `secrets.json`(0600). 환경 변수 `DEEPSEEK_API_KEY`로 덮어쓸 수 있습니다.
- DeepSeek은 정리할 때만 호출되며, 나머지는 모두 Mac에 남습니다.

---

## 권한 및 서명

macOS는 화면 기록 같은 권한을 **코드 서명**으로 기억합니다. **ad-hoc 서명**은 지정 요건이 빌드마다 바뀌는 `cdhash`라서, 재빌드마다 새 앱으로 보고 다시 묻습니다.

`scripts/build.sh`는 가능하면 **Apple Development 인증서**로 서명해 권한이 유지됩니다:

```bash
CODESIGN_IDENTITY="Apple Development: you@example.com (XXXXXXXXXX)" bash scripts/build.sh
```

개인 정보가 없는 **배포용 빌드**(GitHub Release 등):

```bash
bash scripts/package-release.sh   # → dist/CatchMeUp-<version>.zip (ad-hoc, 이메일/Team ID 없음)
```

---

## FAQ

**Q: 화면 기록 권한을 계속 요구합니다.**
A: 인증서로 재빌드(위)하고 설정 → 권한에서 한 번 허용하세요.

**Q: 권한 없이도 쓸 수 있나요?**
A: 네. 알림·캘린더·스크린샷만 사용할 수 없습니다.

**Q: DeepSeek 없이도 되나요?**
A: 정리와 인수인계는 API에 의존합니다. 키가 없어도 수동으로 작업을 관리할 수 있습니다.

---

## 라이선스

[MIT](LICENSE)
