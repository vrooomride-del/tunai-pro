# TUNAI Pro — 파인튜닝 플로우 진단 보고서

> 진단일: 2026-06-20 / 코드 수정 없음, 읽기 전용 세션

---

## [1] 스피커/DSP 보드 탐지

- **상태**: 부분구현
- **관련 파일**:
  - `lib/core/profiles/system_profile.dart`
  - `lib/core/dsp/adau1701_adapter.dart`
  - `lib/core/dsp/adau1466_adapter.dart`
  - `lib/features/dsp/dsp_screen.dart` (`_BoardSelector`)
- **설명**: DSP 화면 상단 `_BoardSelector`에서 3개 프로파일(TUNAI ONE / Isobarik / TUNAI REFERENCE) 중 런타임 전환 가능. `systemProfileProvider`(Riverpod)로 전역 공유. ADAU1701 어댑터는 PEQ/크로스오버/Gain/Delay/SubsonicFilter 전부 UART 프레임 생성까지 구현.
- **갭**:
  - **ADAU1466 어댑터 5개 메서드 전부 `UnimplementedError`** — SigmaStudio PRAM 주소맵 미확정. 파란보드 선택 시 "전송 비활성" 배너 표시, `sendToDsp()` 즉시 false 반환
  - ADAU1701 어댑터도 `_gainBase` / `_delayBase`가 `0x0000` TODO — Gain·Delay 명령이 실제로 전송되지 않음
  - 자동 탐지(연결된 장치에서 보드 종류 자동 식별) 없음

---

## [2] T/S 파라미터 + 크로스오버 제안

- **상태**: 구현완료 (핵심 플로우), 단 FRD 그래프 없음
- **관련 파일**:
  - `lib/features/driver/driver_screen.dart`
  - `lib/features/driver/driver_profile.dart`
  - `lib/core/frd_parser.dart`
- **설명**:
  - DRIVERS 탭: FRD/ZMA 파일 임포트 → `FrdParser.parseFrd()` / `extractTs()`로 T/S 파라미터 추출 + 화면 표시
  - CROSSOVER 탭 AUTO 버튼: ① FRD 양쪽 모두 있으면 `recommendCrossover()`로 주파수 교차점 탐색, ② T/S만 있으면 `Fs × (Qts에 따른 3~5배수)` 계산
  - "DSP에 적용" 버튼: 채널 타입(woofer/tweeter/mid)에 맞춰 HP/LP 필터를 `dspProvider`에 직접 주입 (3웨이 포함)
- **갭**:
  - FRD 임포트 후 **주파수 응답 그래프 없음** — 포인트 수·주파수 범위만 텍스트 표시
  - `recommendCrossover()`가 단순 교차점 탐색이라 정확도 제한적 (피크/롤오프 기반 아님)
  - 3웨이 미드 채널 `case ChannelType.mid:` 분기 중복 가능성

---

## [3] 안전 기본값 DSP 자동 적용

- **상태**: 미구현 (데이터 모델만 존재)
- **관련 파일**:
  - `lib/core/dsp_engine.dart` (`SafetyProfile` 클래스)
  - `lib/core/speaker_profile.dart` (`recommendedHpfFreq`, `maxBassBoostDb`)
  - `lib/features/mic/speaker_profile_selector.dart`
- **설명**: `SafetyProfile.fromTs(fs, qts, xmax)`로 HPF 권장 주파수(`fs × 0.85`)와 최대 베이스 부스트를 계산. `SpeakerProfile`에도 동일 계산 존재. speaker_profile_selector에서 선택한 프로파일의 HPF 권장값을 UI에 표시.
- **갭**:
  - 계산된 권장 HPF가 실제 DSP에 **자동 적용되는 코드 없음**
  - `writeSubsonicFilter()`는 어댑터에 정의되어 있지만 **어디서도 호출되지 않음**
  - T/S 없을 때 기본 HPF fallback(예: 60Hz)도 없음
  - 스피커 보호 기능이 "있는 것처럼 보이지만 실제로 작동하지 않는" 상태

---

## [4] 측정 → AI 튜닝 플로우 (Pro 버전)

- **상태**: 구현완료 (end-to-end 연결됨)
- **관련 파일**:
  - `lib/features/mic/mic_measurement_controller.dart`
  - `lib/features/dsp/widgets/ai_panel.dart`
  - `lib/core/ai_tuning_service.dart`
  - `lib/features/dsp/dsp_screen.dart`
  - `lib/features/peq/peq_screen.dart`

**단계별 연결 현황**:

| 단계 | 연결 상태 |
|---|---|
| 핑크노이즈 생성 + 동시 녹음 | ✅ Paul Kellet 알고리즘, 65536pt FFT, 1/3옥타브 스무딩 |
| 채널별 순차 측정 + 크로스오버 자동 적용 | ✅ `startChannelMeasurement()` |
| frequencyResponse → AI 패널 전달 | ✅ `DspScreen`이 `micMeasurementProvider`를 읽어 `AiTuningPanel`에 전달 |
| AI 호출 (Firebase Functions) | ✅ `AiTuningService.suggest()` HTTP POST |
| 밴드별 APPLY / APPLY ALL | ✅ `dspProvider.updateOutputBand()` 호출 |
| SEND TO DSP (ADAU1701) | ✅ 수동으로 SEND 버튼 누르면 전송 |
| 수동 PEQ 편집 | ✅ 출력 20밴드 + 입력 10밴드 편집기 |

- **갭**:
  - `AiTuningPanel._ask()` 호출 시 `speakerProfile`·`systemProfile` 파라미터가 **null로 전달** — AI가 스피커 물성 없이 응답
  - APPLY 후 `sendToDsp()`가 **자동 호출되지 않음** — 사용자가 수동으로 SEND TO DSP 버튼을 별도로 눌러야 함

---

## [5] DspAdapter 추상화 완성도 (Pro 모드 설계)

- **상태**: 구현완료 (추상화), 부분구현 (실제 하드웨어 커버리지)
- **관련 파일**:
  - `lib/core/dsp/dsp_adapter.dart`
  - `lib/core/dsp_engine.dart`
  - `lib/core/profiles/system_profile.dart`
- **설명**: `DspAdapter` 추상 클래스(5개 메서드), `SystemProfile.adapterFactory` 팩토리 패턴, `RawWriteFn` 통신 레이어 주입 구조가 깔끔하게 분리. `DspEngine`은 순수 Dart — Flutter Web/Desktop/Mobile 어디서나 재사용 가능.
- **갭**:
  - `tunai_pro` 레포에만 있어 모바일 앱에서 재사용하려면 **공통 패키지로 추출 필요**
  - ADAU1466 어댑터가 stub 상태 → 파란보드 사용자에게 Pro 앱이 현재 무용지물

---

## [6] 커뮤니티/프리셋 공유

- **상태**: 구현완료 (서버 연동 포함)
- **관련 파일**:
  - `lib/features/community/community_screen.dart`
  - `lib/core/api_service.dart`
- **설명**: `https://api.tunai.kr` REST API 완전 연동. 프리셋 조회(인기순/최신순), 업로드, DSP 즉시 적용, 게시판(전체/튜닝팁/리뷰/Q&A/자유) 읽기/쓰기, 카카오 소셜 로그인까지 구현. 프리셋 로컬 저장(`SharedPreferences`) + 서버 업로드 경로 분리.
- **갭**:
  - `uploadPreset(price:)` API 파라미터 있으나 **UI에서 가격 설정 화면 없음** — 유료 판매 미완성
  - `likePreset()` API는 있으나 **좋아요 버튼 UI 없음**
  - 프리셋 교환이 PEQ 밴드(`fps_json`)만 주고받음 — 측정 데이터(`peaks_json`) 연동 없음

---

## 다음 세션 우선순위 제안

| 순위 | 작업 | 이유 |
|---|---|---|
| P1 | **ADAU1466 어댑터 구현 + ADAU1701 Gain/Delay 주소 확정** | 파란보드 사용자 DSP 전송 완전 불가 — 가장 큰 기능 블로커 |
| P2 | **안전 HPF 자동 적용** (`writeSubsonicFilter()` 연결) | 스피커 보호 기능이 코드엔 있지만 실제 동작 안 함 |
| P3 | **AI 패널에 SpeakerProfile / SystemProfile 전달** | 1~2줄 수정으로 AI 응답 품질 즉시 향상 |
| P4 | **FRD 주파수 응답 그래프** | DRIVERS 탭에서 임포트 후 곡선 안 보임 — 소비자 완성도 체감 직결 |
| P5 | **APPLY 후 sendToDsp() 자동 호출 옵션** | 현재 APPLY → SEND TO DSP 두 번 눌러야 반영 — UX 마찰 |
