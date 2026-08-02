// TUNAI PRO UI v2 — common channel-selector sidebar.
//
// Replaces the per-tab private channel-list widgets duplicated across
// delay_tab.dart / gain_tab.dart / phase_tab.dart / peq_tab.dart / xo_tab.dart.
// Not wired into those tabs yet — each keeps its own `PeqChannelState` /
// `DriverChannel` model wired to its own list widget for now.
//
// Presentation-only: [ChannelSelectorItem] carries plain strings/colors, not
// any acoustic/tuning domain type, so this file has zero dependency on
// pro_acoustic_data.dart, pro_tuning_data.dart, or any other domain model.
// Each tab is responsible for mapping its own channel model to
// [ChannelSelectorItem] when it migrates onto this component.

import 'package:flutter/material.dart';

import '../design/pro_tokens.dart';

/// One row's worth of display data. No acoustic/tuning semantics — [status]
/// is a plain color the caller assigns any meaning to (e.g. "has active PEQ
/// bands", "XO configured", "measured").
class ChannelSelectorItem {
  final String id;
  final String label;
  final String? subtitle;
  final Color? status;

  const ChannelSelectorItem({
    required this.id,
    required this.label,
    this.subtitle,
    this.status,
  });
}

class ChannelSelectorSidebar extends StatelessWidget {
  final List<ChannelSelectorItem> items;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final String title;
  final double width;

  const ChannelSelectorSidebar({
    super.key,
    required this.items,
    required this.onSelected,
    this.selectedId,
    this.title = 'Channels',
    this.width = 192,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: ColoredBox(
          color: ProColors.panel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    ProSpacing.md, ProSpacing.md, ProSpacing.md, ProSpacing.sm),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: ProColors.textTertiary,
                    fontSize: ProTypeScale.label,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final active = item.id == selectedId;
                    return _ChannelRow(
                      item: item,
                      active: active,
                      onTap: () => onSelected(item.id),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
}

class _ChannelRow extends StatelessWidget {
  final ChannelSelectorItem item;
  final bool active;
  final VoidCallback onTap;

  const _ChannelRow({
    required this.item,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: active
            ? ProColors.accent.withValues(alpha: 0.1)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: ProSpacing.md, vertical: ProSpacing.sm),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: active ? ProColors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                if (item.status != null) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: item.status,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: ProSpacing.sm),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.label,
                        style: TextStyle(
                          color: active
                              ? ProColors.textPrimary
                              : ProColors.textSecondary,
                          fontSize: ProTypeScale.secondary,
                          fontWeight:
                              active ? FontWeight.w500 : FontWeight.w400,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle!,
                          style: const TextStyle(
                            color: ProColors.textTertiary,
                            fontSize: ProTypeScale.label,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
