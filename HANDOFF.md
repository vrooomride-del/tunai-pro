# TUNAI 마스터플랜 현황판

> 이 표는 매 세션 시작/종료 시 갱신한다.
> 새 작업으로 새기 전에 반드시 먼저 읽고, 세션 끝나면 변경된 항목만 갱신해서 다음 HANDOFF.md에 그대로 옮긴다.

**업데이트: 2026-06-20 (포트 자동감지 버그 수정 + 보드 자동탐지 완료)**

---

## A. 제품 플로우 6단계 현황 (모바일 + Pro)

| # | 단계 | 모바일 상태 | Pro 상태 | 비고 |
|---|---|---|---|---|
| 1 | 스피커/DSP 보드 탐지 | ✅ BLE advName+UUID 자동탐지 | ✅ BLE 동일 이식 | UART 이름 기반 탐지는 다음 세션. ADAU1466 stub 유지 |
| 2 | 유닛 물성 기반 크로스오버 제안 | ✅ T/S+FRD 추천 | ⚠️ 크로스오버 UI 100% / DSP 50% — writeDelay/writeGain stub | 선결: SigmaStudio PRAM 주소 export. PRO_CROSSOVER_AUDIT.md 참고 |
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
| ADAU1466 어댑터 | stub, 보드 도착 대기 |
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
| ADAU1466 어댑터 구현 | ❌ 보드 도착 대기 | 물리적 전제조건 |
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
