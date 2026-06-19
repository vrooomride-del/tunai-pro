import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import 'peq_controller.dart';
import '../../core/dsp_engine.dart';
import '../../core/api_service.dart';

class PeqScreen extends ConsumerWidget {
  const PeqScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(peqProvider);
    final ctrl = ref.read(peqProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Column(
        children: [
          _TopBar(isDirty: state.isDirty, onReset: ctrl.resetAll),
          _BodePlot(response: state.frequencyResponse, filters: state.filters),
          const Divider(color: Colors.white12, height: 1),
          _FilterBandSelector(
            filters: state.filters,
            selectedIndex: state.selectedIndex,
            onSelect: ctrl.selectFilter,
            onAdd: ctrl.addFilter,
            onRemove: ctrl.removeFilter,
          ),
          const Divider(color: Colors.white12, height: 1),
          // 필터 편집 영역 — 남은 공간 차지 후 스크롤
          Expanded(
            child: SingleChildScrollView(
              child: state.filters.isNotEmpty
                  ? _FilterEditor(
                      filter: state.filters[state.selectedIndex],
                      index: state.selectedIndex,
                      ctrl: ctrl,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          // 하단 전송 버튼 — 항상 하단 고정
          _SendBar(onSend: () {
            final frames = ctrl.buildFrames();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${frames.length}개 필터 전송 준비 완료')),
            );
          }),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  final bool isDirty;
  final VoidCallback onReset;
  const _TopBar({required this.isDirty, required this.onReset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(peqProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Row(
        children: [
          const Text('TUNAI PRO',
              style: TextStyle(color: Colors.white, fontSize: 18,
                  fontWeight: FontWeight.w200, letterSpacing: 6)),
          const SizedBox(width: 12),
          if (isDirty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('UNSAVED',
                  style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1)),
            ),
          const Spacer(),
          // 클라우드 업로드
          GestureDetector(
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final token = await ApiService.getToken();
              if (token == null) {
                messenger.showSnackBar(
                    const SnackBar(content: Text('TUNAI 앱에서 로그인 후 사용하세요.')));
                return;
              }
              if (!context.mounted) return;
              final nameCtrl = TextEditingController(text: 'Pro Preset');
              final roomCtrl = TextEditingController();
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF111111),
                  title: const Text('커뮤니티 공유',
                      style: TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 2)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(controller: nameCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'TITLE',
                          labelStyle: TextStyle(color: Colors.white38, fontSize: 10),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                        )),
                      const SizedBox(height: 8),
                      TextField(controller: roomCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'ROOM TAG',
                          labelStyle: TextStyle(color: Colors.white38, fontSize: 10),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                        )),
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context),
                        child: const Text('취소', style: TextStyle(color: Colors.white38))),
                    TextButton(
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        final snackbar = ScaffoldMessenger.of(context);
                        nav.pop();
                        final fps = ref.read(peqProvider).filters.map((f) => {
                          'f': f.frequency, 'g': f.gainDb, 'q': f.q, 'type': f.type.index
                        }).toList();
                        final res = await ApiService.uploadPreset(
                          title: nameCtrl.text.trim(),
                          description: 'TUNAI Pro 프리셋',
                          fps: fps,
                          roomTag: roomCtrl.text.trim(),
                        );
                        snackbar.showSnackBar(SnackBar(
                          content: Text(res['status'] == 'ok' ? '커뮤니티에 공유됐습니다!' : '공유 실패: ${res["message"]}'),
                        ));
                      },
                      child: const Text('공유', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
            },
            child: const Icon(Icons.cloud_upload_outlined, color: Colors.white38, size: 16),
          ),
          const SizedBox(width: 16),
          // 클라우드 다운로드
          GestureDetector(
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final res = await ApiService.getPresets();
              if (res['status'] != 'ok') return;
              final presets = res['data'] as List;
              if (presets.isEmpty) {
                messenger.showSnackBar(
                    const SnackBar(content: Text('커뮤니티 프리셋이 없습니다.')));
                return;
              }
              if (!context.mounted) return;
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF111111),
                  title: const Text('커뮤니티 프리셋',
                      style: TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 2)),
                  content: SizedBox(
                    width: 400,
                    child: ListView(
                      shrinkWrap: true,
                      children: presets.map<Widget>((p) => ListTile(
                        title: Text(p['title'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                        subtitle: Text('by ${p["nickname"] ?? ""} · ↓${p["downloads"] ?? 0}',
                            style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        onTap: () async {
                          final nav = Navigator.of(context);
                          final snackbar = ScaffoldMessenger.of(context);
                          nav.pop();
                          final fps = p['fps_json'] as List? ?? [];
                          if (fps.isEmpty) {
                            snackbar.showSnackBar(
                                const SnackBar(content: Text('필터 데이터가 없습니다.')));
                            return;
                          }
                          final filters = fps.map((f) => BiquadFilter(
                            frequency: (f['f'] ?? 1000).toDouble(),
                            gainDb: (f['g'] ?? 0).toDouble(),
                            q: (f['q'] ?? 2.0).toDouble(),
                            type: FilterType.values[f['type'] ?? 0],
                          )).toList();
                          ref.read(peqProvider.notifier).loadFilters(filters);
                          snackbar.showSnackBar(
                              SnackBar(content: Text('${p["title"]} 적용됐습니다.')));
                        },
                      )).toList(),
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context),
                        child: const Text('닫기', style: TextStyle(color: Colors.white38))),
                  ],
                ),
              );
            },
            child: const Icon(Icons.cloud_download_outlined, color: Colors.white38, size: 16),
          ),
          const SizedBox(width: 20),
          // 불러오기
          GestureDetector(
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final presets = await ctrl.getSavedPresets();
              if (presets.isEmpty) {
                messenger.showSnackBar(
                    const SnackBar(content: Text('저장된 프리셋이 없습니다.')));
                return;
              }
              if (!context.mounted) return;
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF111111),
                  title: const Text('프리셋 불러오기',
                      style: TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 2)),
                  content: SizedBox(
                    width: 300,
                    child: ListView(
                      shrinkWrap: true,
                      children: presets.map((name) => ListTile(
                        title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 16),
                          onPressed: () async {
                            final nav = Navigator.of(context);
                            await ctrl.deletePreset(name);
                            nav.pop();
                          },
                        ),
                        onTap: () {
                          ctrl.loadPreset(name);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$name 불러왔습니다.')));
                        },
                      )).toList(),
                    ),
                  ),
                ),
              );
            },
            child: const Text('LOAD',
                style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
          ),
          const SizedBox(width: 20),
          // 저장
          GestureDetector(
            onTap: () {
              final nameCtrl = TextEditingController(text: 'Preset ${DateTime.now().millisecondsSinceEpoch}');
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF111111),
                  title: const Text('프리셋 저장',
                      style: TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 2)),
                  content: TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'NAME',
                      labelStyle: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context),
                        child: const Text('취소', style: TextStyle(color: Colors.white38))),
                    TextButton(
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        final snackbar = ScaffoldMessenger.of(context);
                        await ctrl.savePreset(nameCtrl.text.trim());
                        nav.pop();
                        snackbar.showSnackBar(
                            SnackBar(content: Text('${nameCtrl.text} 저장됐습니다.')));
                      },
                      child: const Text('저장', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
            },
            child: const Text('SAVE',
                style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 2)),
          ),
          const SizedBox(width: 20),
          GestureDetector(
            onTap: onReset,
            child: const Text('RESET',
                style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
          ),
        ],
      ),
    );
  }
}

class _BodePlot extends StatelessWidget {
  final List<Map<String, double>> response;
  final List<BiquadFilter> filters;
  const _BodePlot({required this.response, required this.filters});

  @override
  Widget build(BuildContext context) {
    if (response.isEmpty) return const SizedBox(height: 200);

    final spots = response.map((r) {
      final logFreq = log(r['frequency']!) / log(10);
      return FlSpot(logFreq, r['db']!.clamp(-24.0, 24.0));
    }).toList();

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: LineChart(
        LineChartData(
          backgroundColor: Colors.transparent,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Colors.white10, strokeWidth: 0.5),
            getDrawingVerticalLine: (_) =>
                const FlLine(color: Colors.white10, strokeWidth: 0.5),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (v, _) {
                  final freq = pow(10, v).toInt();
                  if ([20, 100, 1000, 10000, 20000].contains(freq) ||
                      [20, 100, 1000, 10000].any((f) => (log(f) / log(10) - v).abs() < 0.05)) {
                    return Text(freq >= 1000 ? '${freq ~/ 1000}k' : '$freq',
                        style: const TextStyle(color: Colors.white24, fontSize: 8));
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 6,
                getTitlesWidget: (v, _) => Text('${v.toInt()}',
                    style: const TextStyle(color: Colors.white24, fontSize: 8)),
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: log(20) / log(10),
          maxX: log(20000) / log(10),
          minY: -24,
          maxY: 24,
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(y: 0, color: Colors.white24, strokeWidth: 0.5),
            ],
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.white,
              barWidth: 1.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBandSelector extends StatelessWidget {
  final List<BiquadFilter> filters;
  final int selectedIndex;
  final Function(int) onSelect;
  final VoidCallback onAdd;
  final Function(int) onRemove;
  const _FilterBandSelector({
    required this.filters, required this.selectedIndex,
    required this.onSelect, required this.onAdd, required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              itemCount: filters.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => onSelect(i),
                onLongPress: () => onRemove(i),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: i == selectedIndex ? Colors.white : Colors.white24,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'EQ${i + 1}',
                    style: TextStyle(
                      color: i == selectedIndex ? Colors.white : Colors.white38,
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (filters.length < 8)
            GestureDetector(
              onTap: onAdd,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Icon(Icons.add, color: Colors.white38, size: 18),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterEditor extends StatelessWidget {
  final BiquadFilter filter;
  final int index;
  final PeqController ctrl;
  const _FilterEditor({required this.filter, required this.index, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 필터 타입 선택
          Row(
            children: FilterType.values.map((t) => GestureDetector(
              onTap: () => ctrl.updateType(index, t),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: filter.type == t ? Colors.white : Colors.white12,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _typeLabel(t),
                  style: TextStyle(
                    color: filter.type == t ? Colors.white : Colors.white24,
                    fontSize: 9, letterSpacing: 1,
                  ),
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 20),

          // 주파수 슬라이더
          _SliderRow(
            label: 'FREQ',
            value: filter.frequency,
            min: 20, max: 20000,
            displayValue: filter.frequency >= 1000
                ? '${(filter.frequency / 1000).toStringAsFixed(1)}kHz'
                : '${filter.frequency.toStringAsFixed(0)}Hz',
            onChanged: (v) => ctrl.updateFrequency(index, v),
            isLog: true,
          ),
          const SizedBox(height: 12),

          // 게인 슬라이더
          _SliderRow(
            label: 'GAIN',
            value: filter.gainDb,
            min: -24, max: 24,
            displayValue: '${filter.gainDb.toStringAsFixed(1)}dB',
            onChanged: (v) => ctrl.updateGain(index, v),
          ),
          const SizedBox(height: 12),

          // Q 슬라이더
          _SliderRow(
            label: 'Q',
            value: filter.q,
            min: 0.1, max: 16,
            displayValue: filter.q.toStringAsFixed(2),
            onChanged: (v) => ctrl.updateQ(index, v),
          ),
        ],
      ),
    );
  }

  String _typeLabel(FilterType t) {
    switch (t) {
      case FilterType.peaking: return 'PEAK';
      case FilterType.lowShelf: return 'LSH';
      case FilterType.highShelf: return 'HSH';
      case FilterType.lowPass: return 'LPF';
      case FilterType.highPass: return 'HPF';
      case FilterType.notch: return 'NOTCH';
    }
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min, max;
  final String displayValue;
  final Function(double) onChanged;
  final bool isLog;
  const _SliderRow({
    required this.label, required this.value,
    required this.min, required this.max,
    required this.displayValue, required this.onChanged,
    this.isLog = false,
  });

  @override
  Widget build(BuildContext context) {
    final sliderValue = isLog
        ? (log(value) - log(min)) / (log(max) - log(min))
        : (value - min) / (max - min);

    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 2)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              trackHeight: 1,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: sliderValue.clamp(0.0, 1.0),
              onChanged: (v) {
                if (isLog) {
                  final logVal = log(min) + v * (log(max) - log(min));
                  onChanged(exp(logVal));
                } else {
                  onChanged(min + v * (max - min));
                }
              },
            ),
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(displayValue,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ),
      ],
    );
  }
}

class _SendBar extends StatelessWidget {
  final VoidCallback onSend;
  const _SendBar({required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white12, width: 0.5)),
      ),
      child: Row(
        children: [
          // UART 포트 선택 (추후 구현)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              children: [
                Icon(Icons.usb, color: Colors.white38, size: 14),
                SizedBox(width: 6),
                Text('UART', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: onSend,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: Text('SEND TO DSP',
                      style: TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 3)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
