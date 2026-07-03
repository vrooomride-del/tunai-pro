# TUNAI 마스터플랜 현황판

> 이 표는 매 세션 시작/종료 시 갱신한다.
> 새 작업으로 새기 전에 반드시 먼저 읽고, 세션 끝나면 변경된 항목만 갱신해서 다음 HANDOFF.md에 그대로 옮긴다.

**업데이트: 2026-07-03 (ADAU1701 주소맵 전면 정정 — PEQ 모듈 없음 확인, XO 8필터블록 구조로 재정의)**

---

## A. 제품 플로우 6단계 현황 (모바일 + Pro)

| # | 단계 | 모바일 상태 | Pro 상태 | 비고 |
|---|---|---|---|---|
| 1 | 스피커/DSP 보드 탐지 | ✅ BLE 기반 완료 | ✅ BLE+UART(VID/PID) 완전 완료 | ADAU1466 stub 유지 |
| 2 | 유닛 물성 기반 크로스오버 제안 | ✅ T/S+FRD 추천 | ✅ 크로스오버+감도매칭 DSP 연결 완료. 위상정합은 Delay 블록 펌웨어 작업 필요 | PRO_CROSSOVER_AUDIT.md 참고 |
| 3 | DSP 자동 적용 (트위터 보호) | ✅ 완료 | — | — |
| 4 | 측정→AI 튜닝→APPLY | ✅ 완료 | ✅ 완료 + AUTO TUNE 반복수렴 | 갭: Closed Loop 모바일 적용 여부 미확인 |
| 5 | 폰용 Pro 모드 | ⏸ 설계완료, FRD 임포트 완료 / ADAU1466 대기 | — | — |
| 6 | 커뮤니티 해시 매칭 | ✅ 완료 | ✅ 완료 | 특허 청구항8 실시됨 |

---

## B. 특허 정합성 현황

| 특허 | 핵심 청구항 | 구현 상태 | 데드라인 |
|---|---|---|---|
| A. SonicCore (6/9 출원) | 청구항1: CCV | ✅ 실시 완료 | 국내우선권 2027-06-09 |
| A. SonicCore | 청구항8: 인클로저 해시 매칭 | ✅ 실시 완료 | 〃 |
| B. Closed Loop (6/12 출원) | 청구항1: 반복수렴 루프 | ✅ 실시 완료 (Pro) | 국내우선권 2027-06-12 |
| C. Modular Tuning Plate | 가변 포트 노브 | ⏸ 미출원 — 설계확정/외부공개 직전 출원 필수 | 트리거 대기 |

---

## C. 하드웨어 트랙

| 항목 | 상태 |
|---|---|
| JAB4 + ICP5 브링업 | ✅ 해결 — VMware USB 패스스루 한계였음. 실물 Windows PC에서 정상 인식. 코드 이슈 아님, 작업 종료 |
| ADAU1466 어댑터 | ✅ 구현 완료 — writeGain/Delay 확정 (Volume SPI 검증, Delay 추정). PEQ/XO 5.27 패턴 구현, 주소 미확정 (SigmaStudio export 필요) |
| Pro 포트 자동감지 | ✅ 완료 — 시스템 가상 포트 필터링 + ICP5/CH34x 자동 선택 구현 |
| 보드 자동탐지 (BLE) | ✅ 완료 — DetectedBoard, advName+fff0 탐지, systemProfileProvider core 이동 |

---

## D. 전체 잔여 작업 후보

| 항목 | 작업 가능 여부 | 비고 |
|---|---|---|
| 1단계 보드 자동탐지 | ✅ 가능 | 다음 후보 |
| 모바일 위상정합/감도매칭 이식 | ✅ 가능 | 2단계 모바일 완성도 상승 |
| Closed Loop 모바일 적용 확인/구현 | ✅ 가능 | 미확인 상태 — 진단 필요 |
| Pro 2단계 잔여 10% 확인 | ✅ 가능 | 무엇이 빠졌는지 진단 필요 |
| ADAU1466 어댑터 구현 | ✅ 완료 — SigmaStudio PEQ/XO 주소 확인 후 _peqBase/_xoBase 교체 필요 | |
| Modular Tuning Plate 출원 | ❌ 설계 확정 대기 | 외부 공개 전 필수 |

---

## 이번 세션 작업 — Pro 포트 자동감지 개선

### 문제
`/dev/cu.Bluetooth-Incoming-Port` (macOS 시스템 Bluetooth 가상 포트)가 포트 목록 최상단에 표시되어 유저가 선택 시 "포트 열기 실패" 에러 발생.

### 수정 내용 (`connect_controller.dart`, `connect_screen.dart`)

1. **시스템 가상 포트 필터링**: `Bluetooth-Incoming-Port`, `Bluetooth-Modem`, `debug-console` 패턴 제외
2. **ICP5/CH34x 자동 선택**: `usbserial`, `wchusbserial`, `usbmodem`, `cu.ICP`, `cu.TUNAI`, `cu.WONDOM` 패턴 중 정확히 1개 매칭 시 자동 선택. 여러 개 또는 없으면 null 유지 → 수동 선택 유도
3. **드롭다운 힌트**: `SELECT PORT (ICP5 / CH34x)`로 명확화

### 커밋
`c89c44d` — fix: UART 포트 자동감지 — 시스템 가상 포트 필터링 + ICP5/CH34x 자동 선택

---

## 이번 세션 추가 — Pro 2단계 크로스오버 진단

### 진단 결과 요약 (PRO_CROSSOVER_AUDIT.md 전문)

| 항목 | 상태 |
|---|---|
| 크로스오버 주파수 추천/적용 | ✅ 작동 중 |
| 위상정합 UI (거리→ms 변환, 미리보기) | ✅ 완료 |
| **위상정합 DSP 실제 적용** | ❌ `_delayBase=0x0000` stub |
| 감도 매칭 로직 | ✅ 완료 (FRD + T/S 폴백) |
| **감도 매칭 DSP 실제 적용** | ❌ `_gainBase=0x0000` stub |
| Vas 크로스오버 활용 | ⚠️ 미사용 — 선택 항목 |

### 완성을 막는 단 하나의 병목
SigmaStudio export (`.h` 또는 `param_data.dat`) — 딜레이/게인 셀 PRAM 주소 확정.  
주소 알면 코드 변경은 상수 2개 교체로 즉시 완료.

### 이번 세션 처리
- snackbar 텍스트 수정: "FRD가 필요" → "감도 정보가 필요 (FRD 또는 T/S)"
- 커밋: `c549639`

---

## 이번 세션 추가 — UART VID/PID 기반 보드 탐지 (1단계 완전 마무리)

### 구현 내용 (`connect_controller.dart`)

`_detectBoardFromUart()` 추가:
1. **VID/PID 우선** — `SerialPort.vendorId/.productId` (포트 열기 전 조회 가능)
   - `0x1A86`(CH34x) + 알려진 PID(`0x7523/5523/7522/55D4`) → `icp5Adau1701` 확신
   - 기타 USB 시리얼 VID(`0x0403 FTDI / 0x10C4 CP210x / 0x067B Prolific`) → `icp5Adau1701` 추정
2. **이름 패턴 폴백** — VID 없으면 `usbserial/wchusbserial/usbmodem` 등으로 추정
3. **ADAU1466 대비** — 파란보드 이름 패턴 → `adau1466` (향후 연결 대비)

`connectUart()`:
- 포트 열기 전 탐지 실행 → `systemProfileProvider` 자동 설정
- `detectedBoard` 상태 업데이트 → 기존 배너 UI 재사용 (화면 변경 없음)
- `disconnectUart()`: `detectedBoard` null 초기화 추가

### 커밋
`6153212` — feat: 1단계 보드 자동탐지 — UART VID/PID 기반 식별 추가

---

## 이번 세션 추가 — ADAU1701 PRAM 주소 확정 반영 (`adau1701_adapter.dart`)

### 배경
Vol/Vol_2/Mute 주소는 이미 확정돼 있었으나 PEQ `_peqBase`(0x0010, 미확정)와 `_peqBands`(20)가
`SystemProfile.maxPeqBands`(ADAU1701=10)와 어긋나 있었고, XO 베이스가 ADAU1466(6채널) 패턴을
그대로 복사해 6채널분 스트라이드를 곱하는 잘못된 추정식이었다.

### 수정 내용
- **PEQ**: `peqBase=14`, 채널당 10밴드×5계수=50워드 연속 배치 (ch0 Woofer 14~63, ch1 Tweeter
  64~113, 20밴드 총합 14~113 — `maxPeqBands=10`과 일치)
- **XO**: 주소 미확정으로 되돌림 (`_xoBase=null`) — SigmaStudio Filter 블록 주소 확인 전까지
  `writeCrossover`/`writeSubsonicFilter` no-op. 기존 "peqBase + 6채널 스트라이드" 추정식은
  근거 없는 값이라 제거
- **Mute 신규 반영**: 채널(밴드) 뮤트 Woofer=11/Tweeter=12, 출력 뮤트 물리 채널별
  805~808 — `writeChannelMute`/`writeOutputMute`로 어댑터에 추가 (DspAdapter 공용 인터페이스
  밖, 아직 UI 미연결 — 현재 `dsp_controller.dart`는 gain을 -96dB로 낮추는 방식으로 뮤트 처리 중)
- Gain(Vol=7/Vol_2=6)과 Delay(펌웨어 미구현, no-op)는 이미 정확해 변경 없음
- ADAU1466 어댑터는 이번 세션 범위 밖 — 변경 없음

### 확인
`flutter analyze` — 0 issues (기존 무관 info 1건 `connect_controller.dart` unnecessary_import 제외)

### 커밋
`0df8d39` — fix(pro): ADAU1701 PRAM 주소 확정 반영 — PEQ 레이아웃/Mute (adau1701_adapter.dart)

---

## 이번 세션 추가 — ADAU1701 주소맵 전면 정정: PEQ→XO (`adau1701_adapter.dart`)

### 배경 (근거) — 반드시 읽을 것
바로 위 세션에서 "PEQ는 채널당 10밴드, 14~113"으로 정정했으나, **이 가정 자체가 틀렸다.** 실제
SigmaStudio export 원본(`JAB4_DSP_Firmware_Hardware_SouceCode_V112_2021_01_12_IC_1_PARAM.h`)
대조 결과, 이 펌웨어에는 PEQ 모듈이 아예 없다. addr 14~799는 전부 크로스오버(XO)용 2차 필터
캐스케이드 8개(스테레오 페어 4쌍) + 210~211 믹서로 구성돼 있었다:

| 블록 | 주소 |
|---|---|
| Filter1_4 | 14~111 |
| Filter1_9 | 112~209 |
| 2XMixer1_3 (XO 믹스 포인트) | 210~211 |
| Filter1_10 | 212~309 |
| Filter1_11 | 310~407 |
| Filter1_5 | 408~505 |
| Filter1_8 | 506~603 |
| Filter1_6 | 604~701 |
| Filter1_7 | 702~799 |

참고용(미사용): SW vol1=800, Gain3/Gain1=801~804, Inv1_10/Inv1_9(극성)=810/811.
Vol(7)/Vol_2(6)/Mute0_2(11/12)/출력뮤트(805~808)는 기존과 일치 — 변경 없음.

**중요**: 이전 세션까지 Pro의 PEQ 탭에서 밴드를 편집하면 `writeBiquad`가 addr 14~113에 실제로
값을 썼는데, 이 범위는 실제로는 Filter1_4/1_9(XO 캐스케이드)와 정확히 겹친다 — 즉 지금까지 Pro에서
ADAU1701 보드에 PEQ를 적용한 적이 있다면 크로스오버 필터가 의도치 않게 덮어써졌을 가능성이 있다.

### 수정 내용
- **PEQ 완전 제거**: `writeBiquad`는 이 펌웨어가 지원하지 않으므로 no-op으로 변경
- **XO 8블록 구조 도입**: `_xoFilterBlockBase`(8개 확정 주소) + `_xoMixerBase`(210) 상수화. 단,
  블록 → (채널, HPF/LPF) 매핑과 블록 내부 스테이지 오프셋(98워드 안에서 계수가 몇 워드 간격으로
  배치되는지)은 아직 미확정 — `_xoBlockIndex()`가 `null`을 반환해 `writeCrossover`/
  `writeSubsonicFilter`는 그대로 no-op 유지. **Boot Camp Windows에서 SigmaStudio .dspproj를
  열어 각 블록의 실제 라벨(우퍼/트위터, LPF/HPF)을 육안 확인 후 반영 필요**
- **PEQ UI 주석 처리**: `system_profile.dart`의 `maxPeqBands`와 `dsp_controller.dart`의 PEQ
  밴드 전송 루프에 "ADAU1701엔 PEQ가 없어 UI에서 밴드를 편집해도 실기기에 전송 안 됨" 주석 추가
  (UI 자체는 이번 스코프에서 손대지 않음 — PEQ 탭을 ADAU1701에서 숨기거나, 펌웨어에 PEQ 블록을
  추가해 재컴파일하는 건 향후 과제)
- Mute(11/12, 805~808)/Vol(6/7)/Delay 로직은 변경 없음, ADAU1466 어댑터도 변경 없음

### 확인
`flutter analyze` — 0 issues (기존 무관 info 1건 `connect_controller.dart` unnecessary_import 제외)

### 다음 세션 필수 선행 작업
Boot Camp Windows + SigmaStudio에서 `.dspproj` 열어 8개 필터 블록의 실제 라벨과 내부 스테이지
워드 레이아웃을 확인해야 XO 기능이 실제로 동작한다. 그 전까지는 크로스오버 조정 UI를 만져도
실기기에 아무 것도 전송되지 않는다(안전한 no-op).

### 커밋
(다음 커밋 예정)
