import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:io';
import '../../core/frd_parser.dart';
import '../../core/profiles/system_profile.dart';
import '../../features/dsp/dsp_controller.dart';
import '../../features/dsp/dsp_state.dart';
import 'driver_profile.dart';

final systemConfigProvider = StateNotifierProvider<SystemConfigNotifier, SystemConfig>(
  (ref) => SystemConfigNotifier(),
);

class SystemConfigNotifier extends StateNotifier<SystemConfig> {
  SystemConfigNotifier() : super(const SystemConfig());
  void updateDriver(DriverProfile d) {
    final list = [...state.drivers];
    final idx = list.indexWhere((e) => e.id == d.id);
    if (idx >= 0) { list[idx] = d; } else { list.add(d); }
    state = state.copyWith(drivers: list);
  }
  void removeDriver(String id) => state = state.copyWith(drivers: state.drivers.where((d) => d.id != id).toList());
  void updateEnclosure(EnclosureConfig enc) => state = state.copyWith(enclosure: enc);
  void updateCrossover(double freq, String type) => state = state.copyWith(crossoverFrequency: freq, crossoverType: type);
}

class DriverScreen extends ConsumerStatefulWidget {
  const DriverScreen({super.key});
  @override
  ConsumerState<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends ConsumerState<DriverScreen> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    final config = ref.watch(systemConfigProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Header(tab: _tab, onTab: (t) => setState(() => _tab = t)),
        Expanded(child: _tab == 0 ? _DriversTab(config: config)
            : _tab == 1 ? _EnclosureTab(config: config)
            : _CrossoverTab(config: config)),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  final int tab; final void Function(int) onTab;
  const _Header({required this.tab, required this.onTab});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('DRIVER & SYSTEM', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 3)),
      const SizedBox(height: 16),
      Row(children: [
        _Tab(label: 'DRIVERS', selected: tab == 0, onTap: () => onTab(0)),
        const SizedBox(width: 8),
        _Tab(label: 'ENCLOSURE', selected: tab == 1, onTap: () => onTab(1)),
        const SizedBox(width: 8),
        _Tab(label: 'CROSSOVER', selected: tab == 2, onTap: () => onTab(2)),
      ]),
      const SizedBox(height: 16),
      const Divider(color: Colors.white12),
    ]),
  );
}

class _Tab extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _Tab({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(color: selected ? Colors.white : Colors.white24),
        borderRadius: BorderRadius.circular(4),
        color: selected ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
      ),
      child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.white38, fontSize: 10, letterSpacing: 1.5)),
    ),
  );
}

class _DriversTab extends ConsumerWidget {
  final SystemConfig config;
  const _DriversTab({required this.config});
  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        _AddBtn(role: DriverRole.woofer, label: '+ WOOFER', ref: ref),
        const SizedBox(width: 8),
        _AddBtn(role: DriverRole.tweeter, label: '+ TWEETER', ref: ref),
        const SizedBox(width: 8),
        _AddBtn(role: DriverRole.midrange, label: '+ MID', ref: ref),
      ]),
      const SizedBox(height: 16),
      ...config.drivers.map((d) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _DriverCard(driver: d))),
      if (config.drivers.isEmpty) Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(8)),
        child: const Column(children: [
          Icon(Icons.speaker, color: Colors.white12, size: 40),
          SizedBox(height: 12),
          Text('드라이버를 추가하세요', style: TextStyle(color: Colors.white24, fontSize: 12)),
          Text('FRD/ZMA 파일 임포트 또는 직접 측정', style: TextStyle(color: Colors.white12, fontSize: 10)),
        ]),
      ),
    ]),
  );
}

class _AddBtn extends StatelessWidget {
  final DriverRole role; final String label; final WidgetRef ref;
  const _AddBtn({required this.role, required this.label, required this.ref});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      final id = '${role.name}_${DateTime.now().millisecondsSinceEpoch}';
      ref.read(systemConfigProvider.notifier).updateDriver(DriverProfile(id: id, name: role.name.toUpperCase(), role: role));
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
    ),
  );
}

class _DriverCard extends ConsumerStatefulWidget {
  final DriverProfile driver;
  const _DriverCard({required this.driver});
  @override
  ConsumerState<_DriverCard> createState() => _DriverCardState();
}

class _DriverCardState extends ConsumerState<_DriverCard> {
  bool _expanded = true;
  String _status = '';

  Future<void> _importFrd() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['frd', 'txt', 'csv']);
    if (r == null) return;
    final content = await File(r.files.single.path!).readAsString();
    final frd = FrdParser.parseFrd(content);
    if (frd.isEmpty) { setState(() => _status = 'FRD 파싱 실패'); return; }
    final sens = FrdParser.calculateSensitivity(frd);
    ref.read(systemConfigProvider.notifier).updateDriver(widget.driver.copyWith(frdData: frd, fromFile: true, fileName: r.files.single.name, sensitivity: sens));
    setState(() => _status = '${frd.length}포인트 · 감도 ${sens.toStringAsFixed(1)}dB');
  }

  Future<void> _importZma() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zma', 'txt', 'csv']);
    if (r == null) return;
    final content = await File(r.files.single.path!).readAsString();
    final zma = FrdParser.parseZma(content);
    if (zma.isEmpty) { setState(() => _status = 'ZMA 파싱 실패'); return; }
    TsParameters? ts;
    try { ts = FrdParser.extractTs(zma); } catch (_) {}
    ref.read(systemConfigProvider.notifier).updateDriver(widget.driver.copyWith(zmaData: zma, tsParams: ts));
    setState(() => _status = ts != null ? 'T/S 추출: $ts' : 'ZMA 로드 완료');
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.driver;
    final roleColor = d.role == DriverRole.tweeter ? Colors.blue.shade200
        : d.role == DriverRole.woofer ? Colors.orange.shade200 : Colors.green.shade200;
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: roleColor, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Text(d.name, style: const TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 1.5)),
            const SizedBox(width: 8),
            Text(d.role.name.toUpperCase(), style: TextStyle(color: roleColor, fontSize: 9, letterSpacing: 1)),
            const Spacer(),
            if (d.hasFrd) const Icon(Icons.equalizer, color: Colors.white38, size: 14),
            if (d.hasZma) const Icon(Icons.show_chart, color: Colors.white38, size: 14),
            if (d.hasTs) const Icon(Icons.check_circle_outline, color: Colors.white38, size: 14),
            const SizedBox(width: 8),
            GestureDetector(onTap: () => ref.read(systemConfigProvider.notifier).removeDriver(d.id),
              child: const Icon(Icons.close, color: Colors.white24, size: 16)),
          ])),
        ),
        if (_expanded) ...[
          const Divider(color: Colors.white12, height: 1),
          Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: _ImportBtn(label: d.hasFrd ? '✓ FRD 로드됨' : 'FRD 임포트', loaded: d.hasFrd, onTap: _importFrd)),
              const SizedBox(width: 8),
              Expanded(child: _ImportBtn(label: d.hasZma ? '✓ ZMA 로드됨' : 'ZMA 임포트', loaded: d.hasZma, onTap: _importZma)),
            ]),
            if (_status.isNotEmpty) ...[const SizedBox(height: 8), Text(_status, style: const TextStyle(color: Colors.white38, fontSize: 10))],
            if (d.hasTs) ...[
              const SizedBox(height: 12),
              const Text('T/S PARAMETERS', style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 2)),
              const SizedBox(height: 8),
              _TsRow('Fs', '${d.tsParams!.fs.toStringAsFixed(1)} Hz'),
              _TsRow('Re', '${d.tsParams!.re.toStringAsFixed(2)} Ω'),
              _TsRow('Qts', d.tsParams!.qts.toStringAsFixed(3)),
              _TsRow('Qes', d.tsParams!.qes.toStringAsFixed(3)),
              _TsRow('Qms', d.tsParams!.qms.toStringAsFixed(2)),
              if (d.sensitivity != null) _TsRow('감도', '${d.sensitivity!.toStringAsFixed(1)} dB'),
            ],
            if (d.hasFrd) ...[
              const SizedBox(height: 12),
              _FrdGraph(frdData: d.frdData),
            ],
          ])),
        ],
      ]),
    );
  }
}

class _ImportBtn extends StatelessWidget {
  final String label; final bool loaded; final VoidCallback onTap;
  const _ImportBtn({required this.label, required this.loaded, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: loaded ? Colors.white38 : Colors.white24),
        borderRadius: BorderRadius.circular(4),
        color: loaded ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
      ),
      child: Center(child: Text(label, style: TextStyle(color: loaded ? Colors.white60 : Colors.white38, fontSize: 10, letterSpacing: 1))),
    ),
  );
}

class _TsRow extends StatelessWidget {
  final String label; final String value;
  const _TsRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      SizedBox(width: 40, child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10))),
      Text(value, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500)),
    ]),
  );
}

class _FrdGraph extends StatelessWidget {
  final List<FrdPoint> frdData;
  const _FrdGraph({required this.frdData});

  @override
  Widget build(BuildContext context) {
    if (frdData.isEmpty) return const SizedBox.shrink();

    final minSpl = frdData.map((p) => p.spl).reduce(min) - 3;
    final maxSpl = frdData.map((p) => p.spl).reduce(max) + 3;

    final spots = frdData
        .where((p) => p.frequency >= 20 && p.frequency <= 20000)
        .map((p) => FlSpot(log(p.frequency) / log(10), p.spl))
        .toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'FRD  ${frdData.first.frequency.toStringAsFixed(0)}–${frdData.last.frequency.toStringAsFixed(0)} Hz  ·  ${frdData.length}pts',
        style: const TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 1),
      ),
      const SizedBox(height: 6),
      SizedBox(
        height: 140,
        child: LineChart(LineChartData(
          backgroundColor: Colors.transparent,
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) => const FlLine(color: Colors.white10, strokeWidth: 0.5),
            getDrawingVerticalLine: (_) => const FlLine(color: Colors.white10, strokeWidth: 0.5),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, interval: 1,
              getTitlesWidget: (v, _) {
                final freq = pow(10, v).toInt();
                if ([20, 100, 1000, 10000].any((f) => (log(f) / log(10) - v).abs() < 0.05)) {
                  return Text(freq >= 1000 ? '${freq ~/ 1000}k' : '$freq',
                      style: const TextStyle(color: Colors.white24, fontSize: 8));
                }
                return const SizedBox.shrink();
              },
            )),
            leftTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, interval: 10,
              getTitlesWidget: (v, _) => Text('${v.toInt()}',
                  style: const TextStyle(color: Colors.white24, fontSize: 8)),
            )),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: log(20) / log(10),
          maxX: log(20000) / log(10),
          minY: minSpl, maxY: maxSpl,
          lineBarsData: [LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.white70,
            barWidth: 1.2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: Colors.white.withValues(alpha: 0.04)),
          )],
        )),
      ),
    ]);
  }
}

class _EnclosureTab extends ConsumerStatefulWidget {
  final SystemConfig config;
  const _EnclosureTab({required this.config});
  @override
  ConsumerState<_EnclosureTab> createState() => _EnclosureTabState();
}

class _EnclosureTabState extends ConsumerState<_EnclosureTab> {
  BoxType _type = BoxType.sealed;
  final _volCtrl = TextEditingController(text: '5.0');
  final _portLCtrl = TextEditingController(text: '65');
  final _portDCtrl = TextEditingController(text: '50');

  @override
  Widget build(BuildContext context) {
    final fb = _type == BoxType.ported ? EnclosureConfig(
      type: _type,
      volume: double.tryParse(_volCtrl.text) ?? 5.0,
      portLength: double.tryParse(_portLCtrl.text),
      portDiameter: double.tryParse(_portDCtrl.text),
    ).portResonance : null;

    return SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('BOX TYPE', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
      const SizedBox(height: 12),
      Row(children: BoxType.values.map((t) => Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
        onTap: () => setState(() => _type = t),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: _type == t ? Colors.white : Colors.white24),
            borderRadius: BorderRadius.circular(4),
            color: _type == t ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
          ),
          child: Text(t.name.toUpperCase(), style: TextStyle(color: _type == t ? Colors.white : Colors.white38, fontSize: 10, letterSpacing: 1)),
        ),
      ))).toList()),
      const SizedBox(height: 20),
      _encField('내부 체적 (L)', _volCtrl),
      if (_type == BoxType.ported) ...[
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _encField('포트 길이 (mm)', _portLCtrl)),
          const SizedBox(width: 12),
          Expanded(child: _encField('포트 직경 (mm)', _portDCtrl)),
        ]),
      ],
      if (fb != null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(6)),
          child: Text('포트 공진 (Fb): ${fb.toStringAsFixed(1)} Hz', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
      ],
      const SizedBox(height: 20),
      ElevatedButton(
        onPressed: () {
          ref.read(systemConfigProvider.notifier).updateEnclosure(EnclosureConfig(
            type: _type, volume: double.tryParse(_volCtrl.text) ?? 5.0,
            portLength: _type == BoxType.ported ? double.tryParse(_portLCtrl.text) : null,
            portDiameter: _type == BoxType.ported ? double.tryParse(_portDCtrl.text) : null,
          ));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장됨'), duration: Duration(seconds: 1)));
        },
        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
        child: const Text('저장', style: TextStyle(fontSize: 12, letterSpacing: 2)),
      ),
    ]));
  }

  Widget _encField(String label, TextEditingController ctrl) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1)),
      const SizedBox(height: 4),
      TextField(
        controller: ctrl, onChanged: (_) => setState(() {}),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: const InputDecoration(isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54))),
      ),
    ],
  );
}

class _CrossoverTab extends ConsumerStatefulWidget {
  final SystemConfig config;
  const _CrossoverTab({required this.config});
  @override
  ConsumerState<_CrossoverTab> createState() => _CrossoverTabState();
}

class _CrossoverTabState extends ConsumerState<_CrossoverTab> {
  final _freqCtrl = TextEditingController(text: '2500');
  final _freq2Ctrl = TextEditingController(text: '400');
  String _xoverType = 'LR24';
  String? _autoHint;

  static CrossoverType _parseCrossoverType(String s) {
    switch (s) {
      case 'LR12': return CrossoverType.lr12;
      case 'LR24': return CrossoverType.lr24;
      case 'LR48': return CrossoverType.lr48;
      case 'BW12': return CrossoverType.butterworth12;
      case 'BW24': return CrossoverType.butterworth24;
      default:     return CrossoverType.lr24;
    }
  }

  void _autoCalc() {
    final woofer  = widget.config.drivers.where((d) => d.role == DriverRole.woofer).firstOrNull;
    final tweeter = widget.config.drivers.where((d) => d.role == DriverRole.tweeter).firstOrNull;
    final mid     = widget.config.drivers.where((d) => d.role == DriverRole.midrange).firstOrNull;

    // FRD 데이터로 추천
    if (woofer?.hasFrd == true && tweeter?.hasFrd == true) {
      final freq = FrdParser.recommendCrossover(woofer!.frdData, tweeter!.frdData);
      setState(() {
        _freqCtrl.text = freq.toStringAsFixed(0);
        _autoHint = 'FRD 분석 기반: ${freq.toStringAsFixed(0)} Hz';
      });
      return;
    }

    // T/S 파라미터로 추천 (Fs 기반)
    String hint = '';
    if (woofer?.hasTs == true) {
      final fs = woofer!.tsParams!.fs;
      final qts = woofer.tsParams!.qts;
      // 우퍼 최대 사용 주파수: Fs × (3~5) — Qts가 낮을수록 더 낮게
      final multiplier = qts < 0.3 ? 3.0 : qts < 0.5 ? 4.0 : 5.0;
      final recommended = (fs * multiplier).clamp(500, 5000);
      _freqCtrl.text = recommended.toStringAsFixed(0);
      hint = '우퍼 Fs=${fs.toStringAsFixed(0)}Hz → 추천 ${recommended.toStringAsFixed(0)}Hz';
    }
    if (mid?.hasTs == true && woofer?.hasTs == true) {
      final midFs = mid!.tsParams!.fs;
      final wooferFs = woofer!.tsParams!.fs;
      _freq2Ctrl.text = (wooferFs * 4).clamp(100, 800).toStringAsFixed(0);
      _freqCtrl.text  = (midFs * 4).clamp(500, 5000).toStringAsFixed(0);
      hint += '\n미드 Fs=${midFs.toStringAsFixed(0)}Hz → 상단 ${_freqCtrl.text}Hz';
    }

    if (hint.isNotEmpty) {
      setState(() => _autoHint = hint);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('드라이버 FRD 또는 T/S 파라미터가 필요합니다')));
    }
  }

  void _applyToDsp(double freq1, double? freq2) {
    final profile = ref.read(systemProfileProvider);
    final dspCtrl = ref.read(dspProvider.notifier);
    final ct = _parseCrossoverType(_xoverType);

    for (int i = 0; i < profile.channels.length; i++) {
      final ch = profile.channels[i];
      switch (ch.type) {
        case ChannelType.woofer:
        case ChannelType.subwoofer:
          dspCtrl.updateLpFilter(i, CrossoverFilter(type: ct, frequency: freq1));
          break;
        case ChannelType.tweeter:
          final hpFreq = freq2 ?? freq1;
          dspCtrl.updateHpFilter(i, CrossoverFilter(type: ct, frequency: hpFreq));
          break;
        case ChannelType.mid:
        case ChannelType.mid:
          if (freq2 != null) {
            dspCtrl.updateHpFilter(i, CrossoverFilter(type: ct, frequency: freq1));
            dspCtrl.updateLpFilter(i, CrossoverFilter(type: ct, frequency: freq2));
          } else {
            dspCtrl.updateHpFilter(i, CrossoverFilter(type: ct, frequency: freq1 * 0.3));
            dspCtrl.updateLpFilter(i, CrossoverFilter(type: ct, frequency: freq1));
          }
          break;
        case ChannelType.fullRange:
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(systemProfileProvider);
    final is3way = profile.crossoverPoints >= 2;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('CROSSOVER TYPE', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: ['LR24', 'LR12', 'LR48', 'BW24', 'BW12'].map((t) => GestureDetector(
          onTap: () => setState(() => _xoverType = t),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: _xoverType == t ? Colors.white : Colors.white24),
              borderRadius: BorderRadius.circular(4),
              color: _xoverType == t ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
            ),
            child: Text(t, style: TextStyle(color: _xoverType == t ? Colors.white : Colors.white38, fontSize: 10)),
          ),
        )).toList()),

        const SizedBox(height: 24),

        // 채널 레이아웃 미리보기
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(6)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: profile.channels.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(e.value.name, style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text(_channelFilterDesc(e.value.type, is3way),
                  style: const TextStyle(color: Colors.white24, fontSize: 9)),
              ]),
            )).toList(),
          ),
        ),

        const SizedBox(height: 20),

        if (is3way) ...[
          const Text('LOW / MID 크로스오버', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
          const SizedBox(height: 8),
          _freqField(_freq2Ctrl),
          const SizedBox(height: 16),
          const Text('MID / HIGH 크로스오버', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
        ] else
          const Text('CROSSOVER FREQUENCY', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),

        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _freqField(_freqCtrl)),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _autoCalc,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(border: Border.all(color: Colors.white38), borderRadius: BorderRadius.circular(4)),
              child: const Text('AUTO', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
            ),
          ),
        ]),

        if (_autoHint != null) ...[
          const SizedBox(height: 8),
          Text(_autoHint!, style: const TextStyle(color: Colors.white38, fontSize: 10, height: 1.5)),
        ],

        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () {
            final freq1 = double.tryParse(_freqCtrl.text) ?? 2500;
            final freq2 = is3way ? double.tryParse(_freq2Ctrl.text) : null;
            ref.read(systemConfigProvider.notifier).updateCrossover(freq1, _xoverType);
            _applyToDsp(freq1, freq2);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${freq1.toStringAsFixed(0)}Hz $_xoverType → DSP 적용 완료'),
            ));
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white, foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
          child: const Text('DSP에 적용', style: TextStyle(fontSize: 12, letterSpacing: 2)),
        ),
      ]),
    );
  }

  Widget _freqField(TextEditingController ctrl) => TextField(
    controller: ctrl,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
    style: const TextStyle(color: Colors.white, fontSize: 13),
    decoration: const InputDecoration(
      isDense: true, suffixText: 'Hz',
      suffixStyle: TextStyle(color: Colors.white38),
      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
    ),
  );

  String _channelFilterDesc(ChannelType type, bool is3way) {
    switch (type) {
      case ChannelType.woofer:
      case ChannelType.subwoofer: return 'LP →';
      case ChannelType.tweeter:   return '← HP';
      case ChannelType.mid:
      case ChannelType.mid:  return '← HP + LP →';
      case ChannelType.fullRange: return 'FULL';
    }
  }
}
