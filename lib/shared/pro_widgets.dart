import 'package:flutter/material.dart';

// ── Colors ───────────────────────────────────────────────────────────────────

const kProBg = Color(0xFF080C10);
const kProSurface = Color(0xFF0F1419);
const kProPanel = Color(0xFF141A21);
const kProBorder = Color(0xFF1E2832);
const kProAccent = Color(0xFF4A9EFF);
const kProGreen = Color(0xFF22C55E);
const kProAmber = Color(0xFFFFB74D);
const kProRed = Color(0xFFEF5350);

// ── Typography helpers ────────────────────────────────────────────────────────

TextStyle proLabel({double size = 11, Color color = Colors.white38, double spacing = 1.5}) =>
    TextStyle(color: color, fontSize: size, letterSpacing: spacing, fontWeight: FontWeight.w400);

TextStyle proTitle({double size = 13, Color color = Colors.white}) =>
    TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w300, letterSpacing: 0.2);

TextStyle proSubtitle({double size = 11, Color color = const Color(0xFF6B7280)}) =>
    TextStyle(color: color, fontSize: size, height: 1.6);

TextStyle proValue({double size = 12, Color color = const Color(0xFF9CA3AF)}) =>
    TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w400);

// ── Status Pill ───────────────────────────────────────────────────────────────

class ProStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const ProStatusPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      border: Border.all(color: color.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w500)),
  );
}

// ── Quick Stat (public) ───────────────────────────────────────────────────────

class ProQuickStat {
  final String label;
  final String value;
  const ProQuickStat(this.label, this.value);
}

// ── Placeholder Workbench Tab ─────────────────────────────────────────────────

class WorkbenchPlaceholder extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<ProQuickStat>? stats;

  const WorkbenchPlaceholder({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: kProAccent.withValues(alpha: 0.6), size: 18),
            const SizedBox(width: 10),
            Text(title, style: proTitle(size: 16)),
          ]),
          const SizedBox(height: 8),
          Text(subtitle, style: proSubtitle()),
          const SizedBox(height: 24),

          // Graph placeholder
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: kProSurface,
              border: Border.all(color: kProBorder),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: Colors.white10, size: 36),
                const SizedBox(height: 12),
                Text('No data', style: proLabel(color: Colors.white24)),
              ]),
            ),
          ),

          if (stats != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: stats!.map((s) => _StatChip(stat: s)).toList(),
            ),
          ],

          const SizedBox(height: 20),
          _ReadyBanner(title: title),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final ProQuickStat stat;
  const _StatChip({required this.stat});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(stat.label, style: proLabel(size: 9)),
      const SizedBox(height: 4),
      Text(stat.value, style: proValue(size: 13, color: Colors.white70)),
    ]),
  );
}

class _ReadyBanner extends StatelessWidget {
  final String title;
  const _ReadyBanner({required this.title});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(children: [
      const Icon(Icons.hourglass_empty_outlined, color: Colors.white24, size: 14),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          '$title will be active once a project is loaded and hardware is connected.',
          style: proSubtitle(size: 11),
        ),
      ),
    ]),
  );
}

// ── Pro Card (for Home) ───────────────────────────────────────────────────────

class ProHomeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool primary;

  const ProHomeCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: primary ? kProAccent.withValues(alpha: 0.08) : kProSurface,
          border: Border.all(
            color: primary ? kProAccent.withValues(alpha: 0.4) : kProBorder,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: primary ? kProAccent : Colors.white38, size: 18),
            const Spacer(),
            if (primary)
              const Icon(Icons.arrow_forward, color: kProAccent, size: 14),
          ]),
          const SizedBox(height: 14),
          Text(title, style: proTitle(size: 13, color: primary ? Colors.white : Colors.white70)),
          const SizedBox(height: 5),
          Text(subtitle, style: proSubtitle(size: 11)),
        ]),
      ),
    );
  }
}
