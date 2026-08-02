// TUNAI PRO UI v2 — Workspace Home hero header (Phase 4-A-1).
//
// Pure identity/branding header: no state, no callbacks. Same text content
// as the previous inline header in workspace_home.dart, restyled onto v2
// tokens. Kept deliberately simple — a title, a one-line descriptor, and a
// quiet caption — no bordered "chip" chrome, per the "premium and simple,
// not an engineering dashboard" direction.

import 'package:flutter/material.dart';

import '../../../shared/design/pro_tokens.dart';

class HomeHeroHeader extends StatelessWidget {
  const HomeHeroHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          ProSpacing.xxl, ProSpacing.xl, ProSpacing.xxl, ProSpacing.xl),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ProColors.border, width: 0.5)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'TUNAI PRO',
            style: TextStyle(
              color: ProColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w300,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Acoustic Intelligence Workstation',
            style: TextStyle(
              color: ProColors.accent.withValues(alpha: 0.85),
              fontSize: ProTypeScale.secondary,
              letterSpacing: 0.6,
            ),
          ),
        ]),
        const Spacer(),
        const Text(
          'AI suggests · Expert verifies · AOS protects · DSP executes',
          style: TextStyle(
            color: ProColors.textTertiary,
            fontSize: ProTypeScale.secondary,
          ),
        ),
      ]),
    );
  }
}
