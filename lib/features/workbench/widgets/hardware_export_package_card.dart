// TUNAI PRO UI v2 — Hardware Tab extraction (Phase 3-C-2D).
//
// UI extraction only: this is the same widget that lived as the private
// `_ExportPackagePanel` class inside hardware_tab.dart, moved verbatim
// (renamed to a public class so it can be imported) with no change to the
// null-package placeholder text, the ProInfoRow field list, or the
// Sigma Mapping / Fixed-point Draft presence checks. It does not touch
// export package generation, the DSP export data model, providers, or
// controllers. `protection` is kept as `dynamic` and unused in build(),
// exactly as it was in hardware_tab.dart — not cleaned up here.

import 'package:flutter/material.dart';

import '../../../core/pro_export_data.dart';
import '../../../shared/pro_widgets.dart';
import '../../../shared/components/info_row.dart';

class HardwareExportPackageCard extends StatelessWidget {
  final DspExportPackage? pkg;
  final dynamic protection; // ProtectionProjectState
  const HardwareExportPackageCard({super.key, this.pkg, this.protection});

  @override
  Widget build(BuildContext context) {
    if (pkg == null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, color: Colors.white24, size: 13),
          const SizedBox(width: 8),
          Text('No export package. Generate an export draft first.',
              style: proSubtitle()),
        ]),
      );
    }

    final hasMapping = pkg!.sigmaMappingReferenceJson != null;
    final hasFP = pkg!.fixedPointDraftJson != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ProInfoRow(label: 'Target', value: pkg!.targetPlatform.label),
        const SizedBox(height: 4),
        ProInfoRow(label: 'Format', value: pkg!.format.label),
        const SizedBox(height: 4),
        ProInfoRow(label: 'Status', value: pkg!.status.label),
        const SizedBox(height: 4),
        ProInfoRow(label: 'Sigma Mapping', value: hasMapping ? 'Present' : 'Not generated'),
        const SizedBox(height: 4),
        ProInfoRow(label: 'Fixed-point Draft', value: hasFP ? 'Present' : 'Not generated'),
        const SizedBox(height: 4),
        ProInfoRow(label: 'Warnings', value: '${pkg!.warningCount}'),
      ]),
    );
  }
}
