// ── TUNAI PRO Phase 3-C — Measurement Microphone Profile Manager ───────────
//
// Project-scoped CRUD over ProProject.microphoneProfiles + selection of
// ProProject.selectedMicrophoneProfile. Reuses Phase 3-B's
// CalibrationFileParser (no parser duplication) and the pure safety rules in
// core/calibration/microphone_profile_edit_rules.dart (no logic duplication
// between this dialog and the Measure tab status card).

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/calibration/calibration_parser.dart';
import '../../core/calibration/calibration_types.dart';
import '../../core/calibration/microphone_catalog.dart';
import '../../core/calibration/microphone_profile_edit_rules.dart';
import '../../core/pro_project.dart';
import '../../core/pro_project_store.dart';
import '../../shared/pro_widgets.dart';
import 'calibration_curve_preview.dart';

Future<void> showMicrophoneProfileManagerDialog(
  BuildContext context, {
  required String projectId,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => MicrophoneProfileManagerDialog(projectId: projectId),
  );
}

class MicrophoneProfileManagerDialog extends ConsumerStatefulWidget {
  final String projectId;
  const MicrophoneProfileManagerDialog({super.key, required this.projectId});

  @override
  ConsumerState<MicrophoneProfileManagerDialog> createState() =>
      _MicrophoneProfileManagerDialogState();
}

enum _View { list, editor }

enum _Kind { supported, tunai, custom }

class _MicrophoneProfileManagerDialogState
    extends ConsumerState<MicrophoneProfileManagerDialog> {
  _View _view = _View.list;
  _Kind _kind = _Kind.custom;
  late MeasurementMicrophoneProfile _draft;
  late TextEditingController _manufacturerCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _serialCtrl;
  late TextEditingController _connectionCtrl;
  late TextEditingController _inputDeviceCtrl;
  late TextEditingController _sensitivityCtrl;
  late TextEditingController _splRefCtrl;

  CalibrationParseResult? _pendingParse;
  CalibrationAngle _pendingAngleOverride = CalibrationAngle.unspecified;
  String? _importError;

  ProProject? get _project => ref
      .watch(proProjectStoreProvider)
      .projects
      .where((p) => p.id == widget.projectId)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    // The editor's controllers are `late` — initialized here (not just when
    // the user opens the editor) so dispose() is always safe even if the
    // dialog is closed while still on the list view.
    final now = DateTime.now();
    _draft = MeasurementMicrophoneProfile(
      id: 'mic_${now.microsecondsSinceEpoch}',
      manufacturer: '',
      model: '',
      connectionType: 'USB',
      calibrationSource: CalibrationSource.uncalibrated,
      createdAt: now,
      updatedAt: now,
    );
    _resetEditorControllers();
  }

  @override
  void dispose() {
    _manufacturerCtrl.dispose();
    _modelCtrl.dispose();
    _serialCtrl.dispose();
    _connectionCtrl.dispose();
    _inputDeviceCtrl.dispose();
    _sensitivityCtrl.dispose();
    _splRefCtrl.dispose();
    super.dispose();
  }

  // ── Editor lifecycle ───────────────────────────────────────────────────

  void _startNewProfile(_Kind kind) {
    final now = DateTime.now();
    final id = 'mic_${now.microsecondsSinceEpoch}';
    String manufacturer = '';
    String model = '';
    String connectionType = 'USB';
    if (kind == _Kind.tunai) {
      manufacturer = 'TUNAI';
      model = 'TUNAI Measurement Mic';
    }
    setState(() {
      _kind = kind;
      _draft = MeasurementMicrophoneProfile(
        id: id,
        manufacturer: manufacturer,
        model: model,
        connectionType: connectionType,
        calibrationSource: CalibrationSource.uncalibrated,
        createdAt: now,
        updatedAt: now,
      );
      _resetEditorControllers();
      _pendingParse = null;
      _importError = null;
      _view = _View.editor;
    });
  }

  void _startEditProfile(MeasurementMicrophoneProfile profile) {
    setState(() {
      _kind = profile.calibrationSource == CalibrationSource.tunaiSerialProfile
          ? _Kind.tunai
          : _Kind.custom;
      _draft = profile;
      _resetEditorControllers();
      _pendingParse = null;
      _importError = null;
      _view = _View.editor;
    });
  }

  bool _controllersInitialized = false;

  void _resetEditorControllers() {
    if (_controllersInitialized) {
      _manufacturerCtrl.dispose();
      _modelCtrl.dispose();
      _serialCtrl.dispose();
      _connectionCtrl.dispose();
      _inputDeviceCtrl.dispose();
      _sensitivityCtrl.dispose();
      _splRefCtrl.dispose();
    }
    _controllersInitialized = true;
    _manufacturerCtrl = TextEditingController(text: _draft.manufacturer);
    _modelCtrl = TextEditingController(text: _draft.model);
    _serialCtrl = TextEditingController(text: _draft.serialNumber ?? '');
    _connectionCtrl = TextEditingController(text: _draft.connectionType);
    _inputDeviceCtrl = TextEditingController(text: _draft.inputDeviceId ?? '');
    _sensitivityCtrl =
        TextEditingController(text: _draft.sensitivityMvPa?.toString() ?? '');
    _splRefCtrl =
        TextEditingController(text: _draft.splReferenceDb?.toString() ?? '');
  }

  // ── Persistence helpers ─────────────────────────────────────────────────

  Future<void> _saveRoster(List<MeasurementMicrophoneProfile> roster) async {
    await ref
        .read(proProjectStoreProvider.notifier)
        .updateMicrophoneProfiles(widget.projectId, roster);
  }

  Future<void> _select(MeasurementMicrophoneProfile? profile) async {
    await ref
        .read(proProjectStoreProvider.notifier)
        .updateSelectedMicrophoneProfile(widget.projectId, profile);
  }

  Future<void> _useWithoutCalibration() async {
    await _select(buildUncalibratedSentinelProfile(DateTime.now()));
  }

  Future<void> _duplicate(MeasurementMicrophoneProfile source) async {
    final project = _project;
    if (project == null) return;
    final now = DateTime.now();
    final copy = duplicateProfile(
      source: source,
      newId: 'mic_${now.microsecondsSinceEpoch}',
      now: now,
    );
    await _saveRoster(upsertProfileInRoster(
        roster: project.microphoneProfiles, profile: copy));
  }

  Future<void> _delete(MeasurementMicrophoneProfile profile) async {
    final project = _project;
    if (project == null) return;
    final result = removeProfileFromRoster(
      roster: project.microphoneProfiles,
      deletedId: profile.id,
      currentlySelected: project.selectedMicrophoneProfile,
    );
    await _saveRoster(result.roster);
    if (result.selectionCleared) {
      await _select(null);
    }
  }

  // ── Calibration import ───────────────────────────────────────────────────

  Future<void> _pickCalibrationFile() async {
    if (_kind == _Kind.tunai) {
      final serialError = validateTunaiSerialForImport(_serialCtrl.text);
      if (serialError != null) {
        setState(() => _importError = serialError);
        return;
      }
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['cal', 'txt'],
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    final fileName = result.files.first.name;
    if (path == null) {
      setState(() => _importError = '파일 경로를 읽을 수 없습니다.');
      return;
    }
    final String content;
    try {
      content = await File(path).readAsString();
    } catch (e) {
      setState(() => _importError = '파일을 읽을 수 없습니다: $fileName');
      return;
    }
    final parsed =
        CalibrationFileParser.parse(content: content, sourceIdentity: fileName);
    setState(() {
      _pendingParse = parsed;
      _pendingAngleOverride = parsed.detectedAngle;
      _importError = parsed.isSuccess
          ? null
          : (parsed.errors.isNotEmpty
              ? parsed.errors.first
              : '보정 파일에서 유효한 데이터를 찾지 못했습니다.');
    });
  }

  void _confirmPendingCalibration() {
    final parsed = _pendingParse;
    final curve = parsed?.curve;
    if (parsed == null || curve == null || !parsed.isSuccess) return;

    final effectiveCurve = _pendingAngleOverride == curve.angle
        ? curve
        : CalibrationCurve(
            points: curve.points,
            angle: _pendingAngleOverride,
            validMinFrequencyHz: curve.validMinFrequencyHz,
            validMaxFrequencyHz: curve.validMaxFrequencyHz,
            sourceIdentity: curve.sourceIdentity,
            checksum: curve.checksum,
            interpolationPolicy: curve.interpolationPolicy,
            parserWarnings: curve.parserWarnings,
          );

    final source = _kind == _Kind.tunai
        ? CalibrationSource.tunaiSerialProfile
        : (_kind == _Kind.supported
            ? CalibrationSource.manufacturerFile
            : CalibrationSource.userImported);

    // Record the serial the curve is being imported FOR, at import time.
    // The text field is the user's live input but the draft object was only
    // updated on save, so the draft used to reach updateSerialNumber() still
    // claiming no serial — which read as "the serial changed" and discarded
    // this very curve (Phase 3-E P0).
    final typedSerial = _serialCtrl.text.trim();

    setState(() {
      _draft = applyCalibrationImport(
        profile: _draft.copyWith(
          serialNumber: typedSerial.isEmpty ? null : typedSerial,
          clearSerialNumber: typedSerial.isEmpty,
        ),
        curve: effectiveCurve,
        resultingSource: source,
        now: DateTime.now(),
      );
      _pendingParse = null;
      _importError = null;
    });
  }

  void _clearCalibration() {
    setState(() {
      _draft = _draft.copyWith(
        calibrationSource: CalibrationSource.uncalibrated,
        clearCalibrationCurve: true,
        updatedAt: DateTime.now(),
      );
      _pendingParse = null;
      _importError = null;
    });
  }

  Future<void> _saveDraft() async {
    final project = _project;
    if (project == null) return;

    // §2 — fail closed on an unapplied calibration import.
    //
    // A parsed file sits in _pendingParse until the user applies it. Saving
    // in that state used to silently discard it and persist an UNCALIBRATED
    // profile: a runtime trace showed the file parsing to 615 points and the
    // saved draft still carrying no curve at all, because the apply button
    // lives inside the scrolling form while Save does not.
    // Dropping a calibration the user explicitly imported is never an
    // acceptable outcome, so the save is refused outright — no roster write,
    // no selection change, no dialog close.
    if (_pendingParse != null) {
      setState(() => _importError = '가져온 보정 파일을 먼저 확인해 주세요.');
      return;
    }

    if (_kind == _Kind.tunai) {
      final serialError = validateTunaiSerialForImport(_serialCtrl.text);
      if (serialError != null) {
        setState(() => _importError = serialError);
        return;
      }
    }

    final now = DateTime.now();
    var finalDraft = _draft.copyWith(
      manufacturer: _manufacturerCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      connectionType: _connectionCtrl.text.trim(),
      inputDeviceId: _inputDeviceCtrl.text.trim().isEmpty
          ? null
          : _inputDeviceCtrl.text.trim(),
      clearInputDeviceId: _inputDeviceCtrl.text.trim().isEmpty,
      sensitivityMvPa: double.tryParse(_sensitivityCtrl.text.trim()),
      splReferenceDb: double.tryParse(_splRefCtrl.text.trim()),
      updatedAt: now,
    );
    // Serial number goes through the mismatch guard, not a plain copyWith —
    // changing a TUNAI profile's serial after it already carries a curve
    // must invalidate that curve rather than silently keep it.
    final newSerial =
        _serialCtrl.text.trim().isEmpty ? null : _serialCtrl.text.trim();
    finalDraft =
        updateSerialNumber(profile: finalDraft, newSerial: newSerial, now: now);

    // Selection policy on save (Phase 3-E P0).
    //
    // Saving used to refresh the selection ONLY when this exact profile was
    // already selected. So a user who had "Use Without Calibration" active —
    // or nothing at all — could create a profile, import a calibration file
    // and save it, and the selection stayed on the uncalibrated sentinel:
    // the roster held a fully calibrated microphone while every screen still
    // read "보정 없이 사용 — No Calibration".
    //
    // A profile the user just configured is therefore selected when nothing
    // real is selected yet. An existing, different microphone is never
    // hijacked — switching between real profiles stays an explicit choice in
    // the list.
    final selected = project.selectedMicrophoneProfile;
    final wasSelected = selected?.id == finalDraft.id;
    final nothingRealSelected =
        selected == null || isUncalibratedSentinel(selected);

    await _saveRoster(upsertProfileInRoster(
        roster: project.microphoneProfiles, profile: finalDraft));

    if (wasSelected || nothingRealSelected) {
      await _select(finalDraft);
    }

    if (mounted) setState(() => _view = _View.list);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final project = _project;
    return Dialog(
      backgroundColor: kProPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: kProBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: project == null
            ? const Padding(
                padding: EdgeInsets.all(24), child: Text('Project not found.'))
            : (_view == _View.list
                ? _buildListView(project)
                : _buildEditorView()),
      ),
    );
  }

  // ── List view ────────────────────────────────────────────────────────────

  Widget _buildListView(ProProject project) {
    final selected = project.selectedMicrophoneProfile;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Text('MEASUREMENT MICROPHONE', style: proTitle(size: 14)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Colors.white38),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            selected == null
                ? '측정 마이크가 선택되지 않았습니다.'
                : (isUncalibratedSentinel(selected)
                    ? '보정 없이 사용 중 — 측정 정확도가 낮아질 수 있습니다.'
                    : '현재 선택: ${selected.manufacturer} ${selected.model}'),
            style: proSubtitle(size: 11),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final p in project.microphoneProfiles)
                    _ProfileListTile(
                      profile: p,
                      selected: selected?.id == p.id,
                      onSelect: () => _select(p),
                      onEdit: () => _startEditProfile(p),
                      onDuplicate: () => _duplicate(p),
                      onDelete: () => _confirmDelete(p),
                    ),
                  if (project.microphoneProfiles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('등록된 마이크 프로필이 없습니다.',
                          style: proSubtitle(size: 11)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => _startNewProfile(_Kind.supported),
              icon: const Icon(Icons.list_alt, size: 14),
              label: const Text('Supported Microphone'),
            ),
            OutlinedButton.icon(
              onPressed: () => _startNewProfile(_Kind.tunai),
              icon: const Icon(Icons.verified_outlined, size: 14),
              label: const Text('TUNAI Microphone'),
            ),
            OutlinedButton.icon(
              onPressed: () => _startNewProfile(_Kind.custom),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Custom Microphone'),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: selected == null ? null : () => _select(null),
                child: const Text('선택 해제'),
              ),
              OutlinedButton(
                onPressed: _useWithoutCalibration,
                style: OutlinedButton.styleFrom(foregroundColor: kProAmber),
                child: const Text('보정 없이 계속 (Use Without Calibration)'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(MeasurementMicrophoneProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kProPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: kProBorder),
        ),
        title: Text('Delete Microphone Profile',
            style: proTitle(size: 14, color: kProRed)),
        content: Text(
          '"${profile.manufacturer} ${profile.model}"을(를) 삭제하시겠습니까?\n\n'
          '이 프로필로 이미 캡처된 측정값은 영향을 받지 않습니다.',
          style: proSubtitle(size: 12),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: kProRed)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _delete(profile);
    }
  }

  // ── Editor view ──────────────────────────────────────────────────────────

  Widget _buildEditorView() {
    final isTunai = _kind == _Kind.tunai;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 18),
              onPressed: () => setState(() => _view = _View.list),
            ),
            Text(
              isTunai
                  ? 'TUNAI Microphone'
                  : (_kind == _Kind.supported
                      ? 'Supported Microphone'
                      : 'Custom Microphone'),
              style: proTitle(size: 14),
            ),
          ]),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_kind == _Kind.supported) _buildCatalogPicker(),
                  const _FieldLabel('Manufacturer'),
                  TextField(
                    controller: _manufacturerCtrl,
                    enabled: !isTunai,
                    decoration: const InputDecoration(isDense: true),
                  ),
                  const SizedBox(height: 10),
                  const _FieldLabel('Model'),
                  TextField(
                      controller: _modelCtrl,
                      decoration: const InputDecoration(isDense: true)),
                  const SizedBox(height: 10),
                  _FieldLabel(isTunai
                      ? 'Serial Number (required)'
                      : 'Serial Number (optional)'),
                  TextField(
                      controller: _serialCtrl,
                      decoration: const InputDecoration(isDense: true)),
                  const SizedBox(height: 10),
                  const _FieldLabel('Connection Type'),
                  TextField(
                      controller: _connectionCtrl,
                      decoration: const InputDecoration(isDense: true)),
                  const SizedBox(height: 10),
                  const _FieldLabel('Input Device Label (optional)'),
                  TextField(
                      controller: _inputDeviceCtrl,
                      decoration: const InputDecoration(isDense: true)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('Sensitivity (mV/Pa, optional)'),
                          TextField(
                              controller: _sensitivityCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(isDense: true)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('SPL Reference (dB, optional)'),
                          TextField(
                              controller: _splRefCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(isDense: true)),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _buildCalibrationSection(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // The calibration preview and its apply button live inside the
          // scrolling form, but this action row does not — so a user could
          // press Save having never scrolled far enough to see that an
          // import was still waiting to be applied. This banner puts that
          // outstanding action where Save already is.
          if (_pendingParse != null && _pendingParse!.isSuccess)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: kProAmber.withValues(alpha: 0.08),
                border: Border.all(color: kProAmber.withValues(alpha: 0.45)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_outlined,
                    size: 14, color: kProAmber),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('가져온 보정 파일이 아직 적용되지 않았습니다.',
                      style: TextStyle(color: kProAmber, fontSize: 11)),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _confirmPendingCalibration,
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('보정 파일 적용'),
                ),
              ]),
            ),
          Row(children: [
            if (_importError != null)
              Expanded(
                child: Text(_importError!,
                    style: const TextStyle(color: kProRed, fontSize: 11)),
              ),
            const Spacer(),
            TextButton(
                onPressed: () => setState(() => _view = _View.list),
                child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _saveDraft, child: const Text('Save')),
          ]),
        ],
      ),
    );
  }

  Widget _buildCatalogPicker() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Model'),
          DropdownButton<String>(
            isExpanded: true,
            value: kSupportedMicrophoneCatalog.any((d) =>
                    d.manufacturer == _manufacturerCtrl.text &&
                    d.model == _modelCtrl.text)
                ? '${_manufacturerCtrl.text}|${_modelCtrl.text}'
                : null,
            hint: const Text('Select a supported model'),
            items: [
              for (final d in kSupportedMicrophoneCatalog)
                DropdownMenuItem(
                  value: '${d.manufacturer}|${d.model}',
                  child: Text('${d.manufacturer} ${d.model}'),
                ),
            ],
            onChanged: (v) {
              final descriptor = kSupportedMicrophoneCatalog
                  .firstWhere((d) => '${d.manufacturer}|${d.model}' == v);
              setState(() {
                _manufacturerCtrl.text = descriptor.manufacturer;
                _modelCtrl.text = descriptor.model;
                _connectionCtrl.text = descriptor.connectionType;
              });
            },
          ),
          if (kSupportedMicrophoneCatalog.any((d) =>
              d.manufacturer == _manufacturerCtrl.text &&
              d.model == _modelCtrl.text))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                kSupportedMicrophoneCatalog
                    .firstWhere((d) =>
                        d.manufacturer == _manufacturerCtrl.text &&
                        d.model == _modelCtrl.text)
                    .notes,
                style: proSubtitle(size: 10),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCalibrationSection() {
    final hasCurve = _draft.calibrationCurve != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('CALIBRATION', style: proLabel(size: 10)),
          const Spacer(),
          Text(_draft.calibrationSource.name, style: proSubtitle(size: 10)),
        ]),
        const SizedBox(height: 8),
        if (hasCurve)
          CalibrationCurvePreview(curve: _draft.calibrationCurve)
        else
          Text('보정 파일이 로드되지 않았습니다. 보정 없이 계속할 수 있지만 측정 정확도가 낮아질 수 있습니다.',
              style: proSubtitle(size: 11)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _pickCalibrationFile,
            icon: const Icon(Icons.upload_file, size: 14),
            label: Text(hasCurve
                ? 'Replace Calibration File'
                : 'Import Calibration File'),
          ),
          if (hasCurve)
            TextButton(
                onPressed: _clearCalibration,
                child: const Text('Clear Calibration')),
        ]),
        if (_pendingParse != null) _buildPendingImportPreview(),
      ],
    );
  }

  Widget _buildPendingImportPreview() {
    final parsed = _pendingParse!;
    if (!parsed.isSuccess) {
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: kProRed.withValues(alpha: 0.08),
          border: Border.all(color: kProRed.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Import failed',
                style: TextStyle(color: kProRed, fontSize: 11)),
            const SizedBox(height: 4),
            for (final e in parsed.errors)
              Text(e, style: proSubtitle(size: 10)),
            for (final w in parsed.warnings)
              Text(w, style: proSubtitle(size: 10)),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kProAmber.withValues(alpha: 0.06),
        border: Border.all(color: kProAmber.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.info_outline, size: 13, color: kProAmber),
            const SizedBox(width: 6),
            Text('미리보기 — 아직 적용되지 않았습니다',
                style: proLabel(size: 10, color: kProAmber)),
          ]),
          const SizedBox(height: 8),
          CalibrationCurvePreview(curve: parsed.curve),
          if (parsed.detectedAngle == CalibrationAngle.unspecified) ...[
            const SizedBox(height: 8),
            const _FieldLabel('Orientation (파일에 명시되지 않음 — 확인 필요)'),
            Wrap(spacing: 8, children: [
              for (final a in CalibrationAngle.values)
                ChoiceChip(
                  label: Text(a.label),
                  selected: _pendingAngleOverride == a,
                  onSelected: (_) => setState(() => _pendingAngleOverride = a),
                ),
            ]),
          ],
          if (parsed.warnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final w in parsed.warnings)
                    Text(w, style: proSubtitle(size: 10)),
                ],
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _confirmPendingCalibration,
            icon: const Icon(Icons.check, size: 16),
            label: const Text('보정 파일 적용'),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: proLabel(size: 10)),
      );
}

class _ProfileListTile extends StatelessWidget {
  final MeasurementMicrophoneProfile profile;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  const _ProfileListTile({
    required this.profile,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final state = deriveMicrophoneDisplayState(profile);
    final (label, color) = switch (state) {
      MicrophoneDisplayState.calibrationReady => ('Calibrated', kProGreen),
      MicrophoneDisplayState.explicitlyUncalibrated => (
          'Uncalibrated',
          kProAmber
        ),
      MicrophoneDisplayState.invalid => ('Invalid', kProRed),
      MicrophoneDisplayState.notSelected => ('—', Colors.white38),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: selected ? kProAccent.withValues(alpha: 0.06) : kProSurface,
        border: Border.all(
            color: selected ? kProAccent.withValues(alpha: 0.5) : kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('${profile.manufacturer} ${profile.model}',
                    style: proValue(size: 12, color: Colors.white)),
                const SizedBox(width: 8),
                ProStatusPill(label: label, color: color),
              ]),
              if (profile.serialNumber != null)
                Text('S/N ${profile.serialNumber}',
                    style: proSubtitle(size: 10)),
              Text(profile.connectionType, style: proSubtitle(size: 10)),
            ],
          ),
        ),
        if (selected)
          const Icon(Icons.check_circle, size: 16, color: kProAccent),
        IconButton(
            icon: const Icon(Icons.check, size: 16),
            tooltip: 'Select',
            onPressed: onSelect),
        IconButton(
            icon: const Icon(Icons.edit_outlined, size: 16),
            tooltip: 'Edit',
            onPressed: onEdit),
        IconButton(
            icon: const Icon(Icons.copy_outlined, size: 16),
            tooltip: 'Duplicate',
            onPressed: onDuplicate),
        IconButton(
            icon: const Icon(Icons.delete_outline, size: 16, color: kProRed),
            tooltip: 'Delete',
            onPressed: onDelete),
      ]),
    );
  }
}
