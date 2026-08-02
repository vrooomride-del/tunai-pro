// TUNAI PRO UI v2 — common graph outer frame.
//
// Provides the chrome around a graph (title/subtitle, legend row, action
// buttons, bordered surface) without knowing anything about how the graph
// itself is drawn. The three existing CustomPainter graphs —
// Adau1701PeqResponseGraph, ProCrossoverResponseGraph, OptimizerPreviewGraph
// (lib/features/workbench/widgets/) — are NOT modified or wrapped by this
// file yet; each still renders its own bordered Container + CustomPaint.
// This frame is what they would each pass their existing CustomPaint into as
// `child` during a later migration turn.

import 'package:flutter/material.dart';

import '../design/pro_tokens.dart';

class AcousticGraphFrame extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final List<Widget> legend;
  final List<Widget> actions;

  /// Fixed height for the graph content area. Null lets [child] size itself.
  final double? height;

  /// The actual graph content (typically a CustomPaint). This frame draws no
  /// axes, curves, or data of its own.
  final Widget child;

  const AcousticGraphFrame({
    super.key,
    this.title,
    this.subtitle,
    this.legend = const [],
    this.actions = const [],
    this.height,
    required this.child,
  });

  bool get _hasHeader =>
      title != null || subtitle != null || actions.isNotEmpty;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(ProSpacing.md),
        decoration: BoxDecoration(
          color: ProColors.panel,
          border: Border.all(color: ProColors.border),
          borderRadius: ProRadius.mediumAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_hasHeader) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null || subtitle != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (title != null)
                            Text(
                              title!,
                              style: const TextStyle(
                                color: ProColors.textPrimary,
                                fontSize: ProTypeScale.secondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: const TextStyle(
                                color: ProColors.textTertiary,
                                fontSize: ProTypeScale.label,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (actions.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions,
                    ),
                ],
              ),
              const SizedBox(height: ProSpacing.sm),
            ],
            if (height != null)
              SizedBox(height: height, child: child)
            else
              child,
            if (legend.isNotEmpty) ...[
              const SizedBox(height: ProSpacing.sm),
              Wrap(
                spacing: ProSpacing.md,
                runSpacing: ProSpacing.xs,
                children: legend,
              ),
            ],
          ],
        ),
      );
}
