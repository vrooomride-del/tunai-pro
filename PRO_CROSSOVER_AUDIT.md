# Pro 2단계 크로스오버 기능 감사 (Audit)

> 작성: 2026-06-20  
> 목적: Pro 2단계 "유닛물성 기반 크로스오버 제안" 잔여 10% 진단

---

## 요약

| 항목 | 상태 | 조치 |
|---|---|---|
| 크로스오버 주파수 추천 (FRD/T/S) | ✅ 완료 | — |
| 2-way / 3-way 전환 | ✅ 완료 | — |
| 위상정합 거리→ms 변환 공식 | ✅ 정확 | — |
| 위상정합 UI (거리 입력, ms 미리보기) | ✅ 완료 | — |
| **위상정합 DSP 실제 적용** | ❌ **미작동** | SigmaStudio PRAM 주소 확정 필요 |
| 감도 매칭 로직 (최저 기준 gain cut) | ✅ 완료 | — |
| 감도 매칭 FRD 없는 채널 폴백 (T/S sensitivity) | ✅ 완료 | — |
| **감도 매칭 DSP 실제 적용** | ❌ **미작동** | 동일: PRAM 주소 확정 필요 |
| Vas 크로스오버 계산 활용 | ⚠️ 미사용 | 다음 세션 검토 |
| snackbar 텍스트 오류 | ✅ 수정됨 | 이번 세션 처리 |

---

## 1. 위상정합 (Acoustic Delay)

### 완성된 것
- `cm / 34.3` — 음속 343m/s 고정, 정확한 공식
- 2-way: 트위터 거리 입력 / 3-way: 트위터 + 미드 거리 입력 모두 지원
- 실시간 ms 미리보기 (`ValueListenableBuilder`)
- `clamp(0, 100ms)` — 100ms ≈ 34.3m, 실용 범위 충분

### 치명적 갭 — 실제 DSP 적용 안 됨
```dart
// adau1701_adapter.dart:79
static const int _delayBase = 0x0000; // ← TODO
Future<void> writeDelay(int channelIndex, double delayMs) async {
  if (_delayBase == 0x0000) return; // 무조건 return!
  ...
}
```
UI에서 "딜레이 적용" 버튼을 눌러도 실제로 DSP에 아무것도 전달되지 않음.  
`dsp_controller.dart` → `adapter.writeDelay()` 호출 경로는 있지만 stub 차단됨.

### 해결 조건
SigmaStudio에서 딜레이 셀 PRAM 주소 export → `_delayBase` 채우면 즉시 작동.  
**실기기 테스트 필요** 항목이 아님 — 코드로 이미 미작동 확인됨.

---

## 2. 감도 매칭 (Sensitivity Match)

### 완성된 것
- FRD가 있으면 `FrdParser.calculateSensitivity()`, 없으면 `driver.sensitivity` 폴백
- 최저 감도 기준 `(minSens - sens).clamp(-40, 0)` gain cut → 헤드룸 보존 설계 올바름
- UI에 채널별 감도 dB 미리보기 표시

### 치명적 갭 — 실제 DSP 적용 안 됨
```dart
// adau1701_adapter.dart:71
static const int _gainBase = 0x0000; // ← TODO
Future<void> writeGain(int channelIndex, double gainDb) async {
  if (_gainBase == 0x0000) return; // 무조건 return!
  ...
}
```
동일한 문제. `updateOutputGain()` → `adapter.writeGain()` → 즉시 return.

### 해결 조건
SigmaStudio에서 게인 셀 PRAM 주소 export → `_gainBase` 채우면 즉시 작동.

### 사소한 수정 (이번 세션 처리)
snackbar: "2개 이상 채널에 FRD가 필요합니다" → "2개 이상 채널의 감도 정보가 필요합니다 (FRD 또는 T/S 파라미터)"  
T/S sensitivity 폴백이 실제로 있는데 FRD가 필요하다고 잘못 안내하던 것.

---

## 3. Vas 활용도

ZMA 파싱 → `TsParameters.vas` 채워짐. 그러나:
- `_autoCalc()`에서 `fs`, `qts`만 사용 — `vas` 미사용
- `EnclosureConfig.portResonance`는 별도 입력한 인클로저 체적(`volume`)으로 계산 — `vas`와 무관
- 크로스오버 주파수 추천에 Vas 미반영

**실질적 영향**: Vas 활용의 가장 명확한 용도는 "우퍼 Fs + Vas + Qts → 최적 인클로저 체적 추정 (Vb = Vas × Qts²)" 같은 인클로저 설계 보조인데, 현재 인클로저 탭은 유저가 직접 입력하는 구조라 Vas 기반 자동 추천이 없음.

크로스오버 추천은 Fs/Qts 기반으로 이미 충분히 실용적이므로 Vas 미사용이 당장 문제가 되진 않음.  
**다음 세션 검토 항목**으로 분류.

---

## 4. 기타 전반 점검

### 필터 타입/슬로프
- LR12/LR24/LR48, BW12/BW24 — 5종 지원, 실용적으로 충분
- 8차 Linkwitz-Riley (LR48, 48dB/oct) 포함 — Pro 레벨에서 충분

### FRD 기반 추천
`FrdParser.recommendCrossover(wooferFrd, tweeterFrd)` — Pro 2-arg 형태로 정확.  
(모바일은 `tweeter:` named 인자. 기능 동일)

### 3-way 미드 채널 처리
`_applyToDsp()`에서 `freq2` null 분기 존재하지만 3-way 조건에서는 항상 `freq2`가 있으므로 dead code. 기능에는 문제 없음.

---

## 결론 및 조치 분류

### 이번 세션 처리 (완료)
- [x] snackbar 텍스트 오류 수정 (`driver_screen.dart:502`)

### 다음 세션 조건부 처리 (SigmaStudio export 선결)
SigmaStudio에서 `.h` 또는 `param_data.dat` export 후:
- `_delayBase` 주소 채우기 → 위상정합 즉시 작동
- `_gainBase` 주소 채우기 → 감도 매칭 즉시 작동

두 작업 모두 코드 변경량은 매우 작음 (상수 2개 교체). 선결 조건: SigmaStudio export.

### 다음 세션 선택 항목
- Vas 기반 인클로저 체적 추천 (인클로저 탭에 "Vas 기반 추천 Vb" 힌트 추가)

### 실기기 테스트 필요 항목
- 딜레이/게인 PRAM 주소 확정 후 JAB4 실물에서 청각 검증
- DSP 반응 속도 (50ms 패킷 간격이 딜레이 적용 시에도 충분한지)

---

## Pro 2단계 완성도 재평가

```
이전 추정: 90%
실제 상태: 기능 UI 100% / DSP 실제 반영 50%
```

크로스오버 주파수 적용(PEQ biquad)은 100% 작동 중.  
위상정합(딜레이)과 감도 매칭(게인)은 UI 완성 / DSP 미연결 상태.  
SigmaStudio PRAM 주소 확정이 2단계 완성의 실질적 마지막 관문.
