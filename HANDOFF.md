# TUNAI 마스터플랜 현황판

> 이 표는 매 세션 시작/종료 시 갱신한다.
> 새 작업으로 새기 전에 반드시 먼저 읽고, 세션 끝나면 변경된 항목만 갱신해서 다음 HANDOFF.md에 그대로 옮긴다.

**업데이트: 2026-07-04 ("Living Speaker" 아키텍처 브리프 기준 현황 점검 — 진단만, 코드 변경 없음)**

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
`0dd831a` — fix(pro): ADAU1701 주소맵 전면 정정 — PEQ 모듈 없음 확인, XO 8필터블록 구조 (adau1701_adapter.dart)

---

## 이번 세션 추가 — XO 블록 라벨/오프셋 확인 시도 (코드 변경 없음, 순수 조사)

### 배경
`writeCrossover`가 no-op인 이유(블록→채널/필터타입 매핑, 블록 내부 오프셋 미확정)를 풀기 위해
Boot Camp Windows + SigmaStudio에서 `.dspproj`를 열어 육안 확인하는 작업이 필요했음. 이 세션에서는
**내가 SigmaStudio GUI를 직접 조작할 수 없어 해당 확인을 완료하지 못했다** — Boot Camp/Windows
파티션이 현재 마운트돼 있지 않았고, 애초에 이 검증은 사람이 스키매틱을 눈으로 보고 신호 흐름을
따라가야 하는 작업이라 자동화가 불가능함.

### 그래도 확인한 것
`.dspproj` 원본 파일이 이미 이 Mac에 있다는 걸 확인함(OneDrive 동기화, Boot Camp 불필요):
`~/Downloads/SONIC CORE/WONDOM/ICP5/JAB4_DSP_ADAU1701_DemoProgram_V112_2021.01.12/
JAB4_DSP_Firmware_Hardware_SouceCode_V112_2021.01.12.dspproj`
(파일명 오타 주의: 폴더/zip은 `2021.01.12`, 파일 자체는 `SouceCode`.)

이 파일은 .NET BinaryFormatter 직렬화 바이너리라 텍스트 파싱으로는 셀 이름/클래스 타입 정도만
나오고, 필터 타입(LPF/HPF)이나 배선 연결 관계, 우퍼/트위터 라벨은 전혀 추출되지 않음(둘 다 GUID로
연결된 바이너리 오브젝트 그래프에 있음 — 스키매틱 캔버스에 사람이 붙인 텍스트 라벨이 없어서 더더욱
불가능). `strings`로 뽑아본 결과 확인된 것: 8개 필터 인스턴스명(`2nd Order Filter1_4`~`1_11`),
`2XMixer1_3`(`ADICtrls.TwoChannelXMixer`/`TwoChanXMixer1940Alg`), `Gain1940AlgNS`×5,
`MuteSWSlewAlg`×3, `Inv1_9`/`Inv1_10`, `SW vol 1`(`Gain3`), `AUX_ADC_0~3` — 전부 이미 알고 있던
정보의 재확인일 뿐, 새로운 매핑 정보는 없음.

### 다음 세션 필수 선행 작업 (변경 없음)
위 `.dspproj`를 Windows에서 SigmaStudio로 열어(Boot Camp 또는 Windows 머신), 8개 필터 블록을
클릭해서 실제 라벨/신호 흐름과 Link Compile Results의 IC Memory 표(파라미터명 순서)를 확인해야
한다. 대안으로, 실기기 상태에서 정품 Miumax 앱으로 크로스오버를 조정하며 BLE/UART 트래픽을
캡처하는 방법도 있음 — 어떤 주소에 어떤 값이 쓰이는지 실측으로 알 수 있어 어쩌면 더 확실할 수
있다(단, 캡처 인프라 구축 필요, 별도 세션 스코프).

### 코드 변경
없음 (순수 조사)

---

## 이번 세션 추가 — writeCrossover 실제 구현 (`adau1701_adapter.dart`)

### 배경
사용자가 SigmaStudio 스키매틱을 직접 확인(2026-07-04)해서 구조를 확정했음:
2웨이 크로스오버, 물리 DAC 4채널(각각 HPF 블록 → LPF 블록 캐스케이드):

| DAC | 역할 | HPF 블록 | LPF 블록 |
|---|---|---|---|
| DAC0 | Tweeter A | Filter1_4 (14~111) | Filter1_11 (310~407, @20kHz≈통과) |
| DAC1 | Tweeter B | Filter1_9 (112~209) | Filter1_10 (212~309, @20kHz≈통과) |
| DAC2 | Woofer A | Filter1_5 (408~505, @150Hz≈무시) | Filter1_6 (604~701) |
| DAC3 | Woofer B | Filter1_8 (506~603, @150Hz≈무시) | Filter1_7 (702~799) |

트위터 체인은 HPF가, 우퍼 체인은 LPF가 실질적 크로스오버 지점 — 반대쪽 블록은 스키매틱
기본값이 사실상 통과/무시로 설정돼 있을 뿐 실제 쓸 수 있는 필터임. 각 98워드 블록 내부의
정확한 스테이지 오프셋과 fixed-point 포맷은 아직 실측 검증되지 않음.

Pro는 채널 인덱스가 모바일과 달리 2개뿐(ch0=Woofer, ch1=Tweeter, 스테레오 링크 — Gain/Mute와
동일 모델)이라, 채널당 L/R 두 DAC 블록 모두에 동일 설정을 write하도록 구현.

### 수정 내용
- `writeCrossover` 실제 구현: `_xoBlockBase`(채널→L/R DAC 블록 주소 리스트) 기반으로 표준
  크로스오버 biquad(`DspEngine.calculateCrossoverBiquads`, Butterworth/LR bw2~lr8) 계산 후
  L/R 두 주소 모두에 write. 계수 순서는 SigmaStudio 표준(B2,B1,B0,A2,A1)으로 재배열 — 기존
  (제거됐던) 구현은 b0,b1,b2,a1,a2 순서였는데 이게 틀렸을 가능성이 있어 이번에 수정
- **안전장치**: `Adau1701Adapter.experimentalXoWriteEnabled` 정적 플래그, 기본 `false`. 블록
  내부 오프셋/계수 포맷이 실측 검증되지 않았기 때문에, 이 플래그가 꺼져 있으면 `writeCrossover`는
  계산만 하고 실제 전송은 하지 않음. UI 쪽 "실험적 기능 동의" 토글 연결은 이번 세션 스코프 밖 —
  상위 레이어에서 명시적으로 옵트인해야 함
- `writeSubsonicFilter`는 계속 no-op — 이 구조엔 별도 subsonic 개념이 없음(Woofer HPF 블록이
  유사한 역할을 할 수 있으나 오프셋/기본값 미검증이라 보류), 사유를 주석으로 남김
- `writeBiquad`(PEQ)/`writeDelay`는 계속 no-op — 각각 "Miumax UI엔 EQ/Delay가 보였으나 이
  스키매틱엔 없음, 별도 확인 필요"로 주석 갱신
- Mute/Vol/Gain/Inv 로직은 변경 없음

### 확인
`flutter analyze` — 0 issues (기존 무관 info 1건 `connect_controller.dart` unnecessary_import 제외)

### 다음 세션 필수 선행 작업
`experimentalXoWriteEnabled=true`로 켜기 전에 반드시 이전 세션에서 설계한 BLE/UART 트래픽 캡처로
블록 내부 오프셋과 계수 포맷을 실측 검증할 것. 검증 없이 실기기에 쏘면 크로스오버가 의도와 다르게
동작하거나 무음/왜곡이 발생할 수 있음 — 실기기 테스트 시 반드시 낮은 볼륨에서 시작하고 이상 있으면
즉시 전원 차단.

### 커밋
`c08e2a6` — feat(pro): ADAU1701 writeCrossover 실제 구현 — 실험적 기능 플래그로 기본 OFF (adau1701_adapter.dart)

---

## 이번 세션 추가 — 신 펌웨어 반영: 표준 5워드 biquad (`adau1701_adapter.dart`)

### ⚠️ 실기기 테스트 전 필수 확인 사항
**이 세션의 주소맵은 SigmaStudio에서 필터 셀을 "General 2nd Order w var Param/Lookup/Slew"
(96워드 lookup)에서 표준 "General (2nd order)"(5워드 biquad)로 교체하고 재컴파일한 신
펌웨어 기준이다. 이 신 펌웨어가 아직 실기기(TUNAI ONE 보드)에 플래시되지 않았을 수 있다.**
`experimentalXoWriteEnabled`를 켠 채로 구 펌웨어가 올라간 보드에 연결하면 완전히 엉뚱한
주소에 값을 쓰게 된다. **실기기 테스트 전 반드시 SigmaStudio로 이 신 펌웨어를 보드에
플래시할 것.**

### 배경
실제 export .h 파일 기준으로 확정된 신 주소맵(필터 블록당 5워드, addr 16~55):

| 블록 | B0 | B1 | B2 | A0 | A1 | 역할 |
|---|---|---|---|---|---|---|
| GenFilter1   | 41 | 42 | 43 | 44 | 45 | Tweeter A HPF |
| GenFilter1_5 | 46 | 47 | 48 | 49 | 50 | Tweeter A LPF |
| GenFilter1_2 | 16 | 17 | 18 | 19 | 20 | Tweeter B HPF |
| GenFilter1_6 | 26 | 27 | 28 | 29 | 30 | Tweeter B LPF |
| GenFilter1_3 | 21 | 22 | 23 | 24 | 25 | Woofer A HPF |
| GenFilter1_7 | 31 | 32 | 33 | 34 | 35 | Woofer A LPF |
| GenFilter1_4 | 36 | 37 | 38 | 39 | 40 | Woofer B HPF |
| GenFilter1_8 | 51 | 52 | 53 | 54 | 55 | Woofer B LPF |

DAC 매핑: DAC0=Tweeter A, DAC1=Tweeter B, DAC2=Woofer A, DAC3=Woofer B.
다른 주소(Vol_2=6, Vol=7, Mute0_2 on/off=11/step=12, Mute1=805~806, Mute0=807~808,
Inv=810~811, I2C=0x34)는 변경 없음.

### 중요 발견 — 슬로프 제한
이전 펌웨어는 채널당 98워드 cascade라 여러 biquad를 이어붙일 수 있다고 가정했었지만,
신 펌웨어는 **필터 블록당 정확히 5워드(2차 biquad 1스테이지)뿐이다.** 즉 bw4/lr4/lr8처럼
2스테이지 이상을 요구하는 슬로프(24dB/oct 이상)는 이 하드웨어로 구현이 불가능하다.
지원 가능한 최대는 bw2/lr2(12dB/oct, 1스테이지)뿐 — `writeCrossover`는 슬로프가 2스테이지
이상을 요구하면 얕은(잘못된) 응답을 보내는 대신 아무 것도 쓰지 않도록 구현했다.

### 수정 내용
- Pro는 채널이 2개뿐(ch0=Woofer, ch1=Tweeter, 스테레오 링크)이라 채널당 L/R 두 DAC 블록
  모두에 동일 설정을 write — 필터 주소 상수/매핑을 위 표대로 전면 재작성 (기존 addr 14~799,
  98워드/블록 → addr 16~55, 5워드/블록)
- 계수 write 순서를 B0,B1,B2,A0,A1로 정정 — SigmaStudio "General 2nd order filter"의
  A0/A1은 `BiquadCoefficients`의 a1/a2와 동일한 자리(0-index 명명 차이일 뿐)라서, 재배열
  없이 그대로 write하면 됨. 이전 세션의 B2,B1,B0,A2,A1 가정은 틀렸었음(구 96워드 lookup
  필터 기준으로 추정한 값)
- `experimentalXoWriteEnabled` 기본값을 `true`로 전환 — 신 주소/포맷이 실측 export .h
  기준으로 확정됐다고 판단
- Fixed-point는 ADAU1701 표준 5.23 가정 유지(이번 세션에서 재확인은 안 됨)
- `writeBiquad`(PEQ)/`writeDelay`는 계속 no-op(이 신 펌웨어에도 PEQ/Delay 모듈 없음),
  `writeSubsonicFilter`도 계속 no-op(subsonic 개념 없음)
- Mute/Vol/Gain/Inv 로직 변경 없음

### 확인
`flutter analyze` — 0 issues (기존 무관 info 1건 `connect_controller.dart` unnecessary_import 제외)

### 다음 세션
1. **신 펌웨어를 실기기에 플래시** (SigmaStudio, .dspproj → Link Compile → Write Latest
   Compilation to E2PROM 등)
2. 저볼륨으로 앱에서 크로스오버 슬라이더 조작 → 실제 필터 반응 확인
3. 이상 있으면 즉시 전원 차단, `experimentalXoWriteEnabled`를 다시 `false`로

### 커밋
`432d08c` — feat(pro): ADAU1701 신 펌웨어 반영 — 표준 5워드 biquad, writeCrossover 활성화 (adau1701_adapter.dart)

---

## 이번 세션 추가 — ADAU1466 주소 전면 반영 (`adau1466_adapter.dart`)

### 배경
`1466_cs42448_18out_eng` 실제 export 대조로 확정된 주소맵 반영. Volume은 기존 검증값과
일치(변경 없음), Delay/PEQ는 신규 확정, HPF/LPF는 구조 자체가 PEQ/Delay와 다르다는 게
새로 발견됨(SafeLoad 방식).

- **Delay** (신규 확정): ch0~5 = 562, 567, 563, 566, 564, 565 — 채널 순서는 Volume과
  동일 CH0~5로 가정(실기기에서 채널별 소리로 확인 필요)
- **PEQ** (신규 확정, 15밴드): base=410, 밴드n(0~14)=410+n×5, addr 410~484. 계수 순서
  B2,B1,B0,A2,A1(ADAU1701 신 펌웨어의 B0,B1,B2,A0,A1과 다름). **채널별 스트라이드는
  이번 export에 없어서, 현재 모든 채널이 410 기준 단일 15밴드를 공유하는 것으로
  구현했다** — 채널별 개별 PEQ가 필요하면 추가 확인 필요
- **HPF/LPF 크로스오버** (신규 발견, 구조 다름): HPF target=24873~24877(slewMode=401),
  LPF target=24878~24882(slewMode=407). SafeLoad 레지스터 영역(24576~24583)과 인접 —
  일반 write가 아니라 SigmaStudio SafeLoad 프로토콜(데이터→ADDRESS→NUM 순서로 써서
  트리거) 필요할 가능성이 높음. **불확실 — 표준 ADI SafeLoad 레지스터 배치를 가정한
  스텁만 작성**하고 `experimentalXoWriteEnabled=false`로 잠금(1701과 동일 패턴). Pro는
  DspEngine에 정수 워드용 프레임 빌더가 없어서 어댑터 내부에 `_buildRawIntFrame`
  로컬 헬퍼를 새로 추가(고정소수점 변환 없이 정수 1워드를 그대로 싣는 프레임)
- Mute 16채널(1081~1096), Compressor(489~542, 범위만) 참고용으로 클래스 doc에 추가
- Volume 로직/주소는 변경 없음

### 확인
`flutter analyze` — 0 issues (기존 무관 info 1건 `connect_controller.dart` unnecessary_import 제외)

### 다음 세션
1. 실기기에서 PEQ/Delay 저볼륨 테스트 — Delay는 채널 순서(562,567,563,566,564,565)가
   실제로 CH0~5와 맞는지 소리로 확인
2. XO(HPF/LPF)는 SafeLoad 프로토콜 자체를 조사(ADI 문서 또는 실측 캡처)한 뒤에만
   `experimentalXoWriteEnabled`를 켤 것 — 지금 스텁은 레지스터 배치를 가정한 것일 뿐
   검증되지 않음

### 커밋
`3019267` — feat(pro): ADAU1466 주소 전면 반영 — PEQ/Delay 확정, XO는 SafeLoad 구조 (adau1466_adapter.dart)

---

## "Living Speaker" 아키텍처 브리프 — Gap Analysis (진단 전용, 코드 변경 없음, 2026-07-04)

### 배경
새 5계층 아키텍처 브리프(AIP/AOS/AIE/AKG/ACM) 도착. tunai(모바일)+tunai_pro 코드베이스
전체를 훑어 이 구조와 얼마나 부합하는지 순수 진단만 수행 — 리팩토링/신규 구현 없음.
**이 보고서는 mobile의 HANDOFF.md와 동일 내용**(두 repo를 함께 조사했기 때문) — 최신
내용은 항상 mobile 쪽 HANDOFF.md 기준으로 볼 것.

### 5계층 매핑

| 계층 | 매핑된 모듈 | 상태 | 격차 |
|---|---|---|---|
| **AIP** (플랫폼) | Firebase(Analytics/Crashlytics/Functions만, Firestore 미사용) + 별도 커스텀 REST API(`api.tunai.kr`, `lib/core/api_service.dart`) | 부분있음 | tunai_pro는 **Firebase 의존성 자체가 없음**(pubspec.yaml에 미포함, `Firebase.initializeApp()` 호출 없음) — AIP는 사실상 모바일에만 걸쳐 있고 Pro는 REST API(auth/community)로만 연결됨 |
| **AOS** (운영체제) | `dsp_controller.dart`(Pro, 프리셋 저장/로드 CRUD, `DspState`) | 부분있음(보호 로직 없음) | 상태머신 아님(단순 CRUD). Factory/User 레이어 분리 없음(`dsp_presets`/`dsp_preset_$name`이 전부 같은 네임스페이스). 트위터 보호 클램프 전무 |
| **AIE** (지능엔진) | `functions/index.js`의 `aiTunePro`(HTTP), `ai_tuning_service.dart`(Pro) | 부분있음 | 타겟커브 개념 없음, LLM 1회 호출 결과 그대로 사용, 서버측 스키마 검증 없음. Pro는 `soundScore` 필드조차 없음(모바일 전용) |
| **AKG** (지식그래프) | `driver_profile.dart`의 `SystemConfig`(DriverProfile 리스트+EnclosureConfig 중첩) | 거의 없음 | `SystemConfig`는 진짜 객체 합성이지만 ID 참조가 없고 측정/튜닝/선호는 포함 안 함, 영속화도 안 됨(메모리에만 존재) |
| **ACM** (실행계층) | `dsp_adapter.dart` 인터페이스 + `adau1701_adapter.dart`/`adau1466_adapter.dart`, `connect_controller.dart`(UART+BLE) | 있음(단, 중복) | 인터페이스는 깔끔하지만 mobile과 완전히 독립된 복사본 — `RawWriteFn` 시그니처가 이미 다름(`Future<bool> Function(List<int>)` vs mobile `Future<void> Function(Uint8List)`) |

### 8개 구조 항목 체크 (요약 — 전체 표는 mobile HANDOFF.md 참고)

| # | 항목 | 상태 |
|---|---|---|
| A | Tuning Package abstraction | 부분있음 — Pro `DspState`는 gain/delay/PEQ/XO 다 포함하지만 mobile My Tune과 공유 모델 없음 |
| B | DSP Platform abstraction | **있음** — `dsp_adapter.dart` |
| C | Factory / User Layer separation | **없음** — "Factory"란 이름도 그냥 덮어쓸 수 있는 프리셋 중 하나일 뿐 |
| D | Safety Validation Layer | **부분있음(핵심 경로엔 없음)** — `dsp_controller.dart:updateOutputBand`가 클램프 없이 저장, `sendToDsp()`까지 검증 전무 |
| E | Measurement History | **없음** |
| F | Target Curve Versioning | **없음** |
| G | Preset and Rollback Structure | 부분있음 — 저장/로드는 가능, undo/rollback 없음 |
| H | AIP-ready Profile Model | **없음** |

### 핵심 안전원칙 점검 — 트위터 보호 우회 가능 여부

**결론: 우회 가능 — 사실상 보호 장치 없음.**

Pro 수동 슬라이더 write-path: `peq_band.dart` 게인 슬라이더(-24~24dB, 트위터/우퍼 동일 위젯)
→ `dsp_controller.dart:updateOutputBand`(클램프 없음) → `sendToDsp()` → `Adau1701Adapter.writeBiquad`
(이 펌웨어엔 PEQ 자체가 없어 no-op — 다른 이유) / `writeGain`(클램프 없음) →
`ConnectController.sendBytes`(값 검증 전혀 없이 raw bytes 전송).

유일한 실제 안전 클램프인 `SafetyProfile.clampBassBoost`(`dsp_engine.dart:294-321`)는
**우퍼(<200Hz) 전용**이고, 그마저 측정 후 1회성 자동튠에만 호출됨. 트위터 보호는
`measurement_mic_screen.dart:388-389`의 **UI 경고 문구로만 존재** — 검증/차단 로직 없음.

Factory preset 보호: **안 됨** — `dsp_presets`/`dsp_preset_$name`이 이름 기반 저장이라
"Factory"라는 이름도 사용자가 그대로 덮어쓸 수 있음.

### 다음 세션
어느 격차부터 메울지는 사용자 판단 필요 — 후보: D(Safety Validation, 트위터 클램프)
/ C(Factory·User 레이어 분리) / H·AKG(통합 프로필 모델). 전체 상세 표는 mobile
HANDOFF.md 참고.

### 커밋
(다음 커밋 예정 — 이번 세션은 진단만, 코드 변경 없음)
