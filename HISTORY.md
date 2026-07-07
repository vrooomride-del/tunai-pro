# TUNAI PRO 개발 히스토리

---

## 2026-06-10

- **초기 커밋** — TUNAI Pro v1 기반 구조
- **GitHub Actions** — macOS / Windows 자동 빌드 + 릴리즈 다운로드 링크
- **DSP 화면** — 20밴드 PEQ + 크로스오버 + TWEETER/MID/WOOFER 채널 순서
- **앱 아이콘** — 전 플랫폼 TUNAI Pro 아이콘 적용
- **Gemini AI 튜닝 어시스턴트** — `gemini-2.5-flash-lite` 연동 (WIP → 작동 확인)
- **macOS 배포 타겟** — 10.15로 통일 (record_macos 호환)

---

## 2026-06-11

- **커뮤니티 / 프로필 탭** — ProCommunityScreen, ProProfileScreen 추가
- **T/S 파라미터** — 스피커 프로파일 입력 → AI 물리 제약 조건 반영
- **SafetyProfile** — Xmax/Fs 기반 DSP 안전 한계 DspEngine 통합
- **린트 수정** — AI 프롬프트 문자열 보간 버그 수정

---

## 2026-06-15

- **DspAdapter 패턴 적용** — ADAU1701/ADAU1466 어댑터 분리
- **칩 명칭 정정** — ADAU1452 → ADAU1466
- **보드 셀렉터** — DSP 화면에서 SystemProfile(보드) 전환 UI 추가
- **하드웨어 독립 DSP 레이어 완성** — 동일 Flutter 코드로 멀티 DSP 지원

---

## 2026-06-20

- **AI 백엔드 교체** — `google_generative_ai` 제거 → Firebase Functions / Vertex AI HTTP 프록시 (`aiTunePro`)
- **마이크 측정 → AI 패널 연결** — 측정 주파수 응답 자동 전달
- **드라이버 T/S → 크로스오버 자동계산** — Fs/Qts/FRD 기반 추천 주파수 계산 → DSP 원클릭 적용
- **채널별 순차 측정** — 채널 솔로(뮤트) → 핑크노이즈 → FFT → 반복 → 크로스오버 교차점 탐색 → DSP 자동 적용
- **DSP 뮤트 실기기 전송** — `setMute()` 호출 시 게인 −96dB로 즉시 DSP 전송
- **마이크 권한 처리** — 거부 시 "시스템 환경설정 열기" 버튼 표시 (macOS 마이크 설정 직접 오픈)

---
