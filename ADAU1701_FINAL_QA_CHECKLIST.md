# ADAU1701 Final QA Checklist — Phase 3-F3 (Mac + real ADAU1701)

Run in order. Each step's "expect" is the pass/fail bar.

1. **Reopen the project** (relaunch the app, don't create a new project).
   Expect: project loads with the correct name and prior state intact.
2. **Calibrated mic still selected.**
   Expect: Measure tab shows the same microphone profile, calibration status unchanged.
3. **Guided Measurement Setup.**
   Expect: setup check runs and passes (or shows a clear, actionable blocker).
4. **Factory 4/4.**
   Expect: all four driver channels show measured/validated status; Factory Guided Tuning shows complete if it was completed previously.
5. **Room Before L/R.**
   Expect: capture Left then Right; both show captured, quality-ready.
6. **Auto PEQ generation.**
   Expect: candidates generated only after Before 2/2 AND quality gate passes.
7. **Approve.**
   Expect: approval succeeds; UI reflects "approved, not yet deployed."
8. **Connect ADAU1701** (USB or BLE).
   Expect: Hardware tab shows connected + handshake pass; Deploy tab's readiness panel shows the session ready.
9. **Deploy.**
   Expect: HardwareApplyFlow runs to completion; result shows written/verified per operation.
10. **Readback verified.**
    Expect: Deploy tab shows "verified" (not ack-only) for every operation; Room After becomes available.
11. **Cmd+Q — fully quit the app** (not just background it).
12. **Relaunch the app.**
13. **Deploy must NOT be requested again.**
    Expect: workflow's next step is "measure Room After," not "deploy" — the persisted VerifiedDeploymentReceipt must prove the correction without a live session.
14. **Hardware row shows disconnected.**
    Expect: Hardware tab / status shows disconnected (or "not checked") — never a false "connected" carried over from before the restart.
15. **Reconnect ADAU1701.**
    Expect: connect/handshake succeeds again; readiness reflects a live session.
16. **Room After L/R.**
    Expect: capture Left then Right; After 2/2 completes.
17. **Closed Loop.**
    Expect: a real verdict is shown (improvedAndComplete / improvedNeedsAnotherCycle / noMeaningfulImprovement / worsened) — never a fabricated percentage.
18. **Cmd+Q again.**
19. **Relaunch.**
20. **Final state persists.**
    Expect: if the prior verdict was improvedAndComplete, Home still shows workflow complete; Hardware row still shows disconnected until reconnected.
21. **worsened/rollback regression check.**
    Expect: if a correction is intentionally regressed (or a prior worsened case is replayed), the rollback CTA still appears, rollback still builds and requires an explicit Deploy approval — never automatic — and a stale receipt from before the rollback is never read as still valid for the ORIGINAL correction after the rollback itself is deployed and verified.

Not covered here (separate, later integration QA): actual audible listening, polarity, physical output-channel mapping.
