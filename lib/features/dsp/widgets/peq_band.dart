import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../dsp_state.dart';

class PeqBandEditor extends StatefulWidget {
  final PeqBand band;
  final int index;
  final bool selected;
  final Function(PeqBand) onChanged;
  final VoidCallback onSelect;

  const PeqBandEditor({
    super.key,
    required this.band,
    required this.index,
    required this.selected,
    required this.onChanged,
    required this.onSelect,
  });

  @override
  State<PeqBandEditor> createState() => _PeqBandEditorState();
}

class _PeqBandEditorState extends State<PeqBandEditor> {
  late TextEditingController _freqCtrl;
  late TextEditingController _gainCtrl;
  late TextEditingController _qCtrl;

  @override
  void initState() {
    super.initState();
    _freqCtrl = TextEditingController(text: _freqText(widget.band.frequency));
    _gainCtrl = TextEditingController(text: widget.band.gainDb.toStringAsFixed(1));
    _qCtrl = TextEditingController(text: widget.band.q.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(PeqBandEditor old) {
    super.didUpdateWidget(old);
    if (old.band.frequency != widget.band.frequency)
      _freqCtrl.text = _freqText(widget.band.frequency);
    if (old.band.gainDb != widget.band.gainDb)
      _gainCtrl.text = widget.band.gainDb.toStringAsFixed(1);
    if (old.band.q != widget.band.q)
      _qCtrl.text = widget.band.q.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _freqCtrl.dispose(); _gainCtrl.dispose(); _qCtrl.dispose();
    super.dispose();
  }

  String _freqText(double f) =>
      f >= 1000 ? '${(f / 1000).toStringAsFixed(f % 1000 == 0 ? 0 : 1)}k'
          : f.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final b = widget.band;
    final sel = widget.selected;

    return GestureDetector(
      onTap: widget.onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? Colors.white.withOpacity(0.05) : Colors.transparent,
          border: Border.all(color: sel ? Colors.white24 : Colors.white12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 밴드 번호 + 활성화 토글
            Row(
              children: [
                Text('${widget.index + 1}',
                    style: TextStyle(
                      color: b.enabled ? Colors.white : Colors.white24,
                      fontSize: 9, letterSpacing: 1,
                      fontFamily: 'monospace',
                    )),
                const Spacer(),
                GestureDetector(
                  onTap: () => widget.onChanged(b.copyWith(enabled: !b.enabled)),
                  child: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: b.enabled ? Colors.white : Colors.transparent,
                      border: Border.all(color: Colors.white38, width: 0.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // 주파수 직접 입력
            _InputField(
              label: 'Hz',
              controller: _freqCtrl,
              enabled: b.enabled,
              onSubmit: (v) {
                double? f = double.tryParse(v.replaceAll('k', ''));
                if (v.endsWith('k')) f = (f ?? 1) * 1000;
                if (f != null) widget.onChanged(b.copyWith(frequency: f.clamp(20, 20000)));
              },
            ),
            const SizedBox(height: 4),

            // Gain 슬라이더 + 입력
            _SliderInput(
              label: 'dB',
              value: b.gainDb,
              min: -24, max: 24,
              controller: _gainCtrl,
              enabled: b.enabled,
              onChanged: (v) => widget.onChanged(b.copyWith(gainDb: v)),
              onSubmit: (v) {
                final g = double.tryParse(v);
                if (g != null) widget.onChanged(b.copyWith(gainDb: g.clamp(-24, 24)));
              },
            ),
            const SizedBox(height: 4),

            // Q 슬라이더 + 입력
            _SliderInput(
              label: 'Q',
              value: b.q,
              min: 0.1, max: 16,
              controller: _qCtrl,
              enabled: b.enabled,
              isLog: true,
              onChanged: (v) => widget.onChanged(b.copyWith(q: v)),
              onSubmit: (v) {
                final q = double.tryParse(v);
                if (q != null) widget.onChanged(b.copyWith(q: q.clamp(0.1, 16)));
              },
            ),
            const SizedBox(height: 6),

            // 필터 타입
            _TypeSelector(
              selected: b.type,
              enabled: b.enabled,
              onChanged: (t) => widget.onChanged(b.copyWith(type: t)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final Function(String) onSubmit;
  const _InputField({required this.label, required this.controller,
      required this.enabled, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: TextStyle(
            color: enabled ? Colors.white38 : Colors.white12,
            fontSize: 8, letterSpacing: 1)),
        const SizedBox(width: 4),
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            style: TextStyle(
                color: enabled ? Colors.white : Colors.white24,
                fontSize: 10, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              border: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white12, width: 0.5)),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white12, width: 0.5)),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white38, width: 0.5)),
            ),
            keyboardType: TextInputType.text,
            onSubmitted: onSubmit,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.k\-]'))],
          ),
        ),
      ],
    );
  }
}

class _SliderInput extends StatelessWidget {
  final String label;
  final double value;
  final double min, max;
  final TextEditingController controller;
  final bool enabled;
  final bool isLog;
  final Function(double) onChanged;
  final Function(String) onSubmit;
  const _SliderInput({
    required this.label, required this.value,
    required this.min, required this.max,
    required this.controller, required this.enabled,
    required this.onChanged, required this.onSubmit,
    this.isLog = false,
  });

  @override
  Widget build(BuildContext context) {
    final sliderVal = isLog
        ? (log(value) - log(min)) / (log(max) - log(min))
        : (value - min) / (max - min);

    return Row(
      children: [
        Text(label, style: TextStyle(
            color: enabled ? Colors.white38 : Colors.white12,
            fontSize: 8, letterSpacing: 1)),
        const SizedBox(width: 4),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: enabled ? Colors.white : Colors.white12,
              inactiveTrackColor: Colors.white12,
              thumbColor: enabled ? Colors.white : Colors.white24,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
              trackHeight: 1,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: sliderVal.clamp(0.0, 1.0),
              onChanged: enabled ? (v) {
                if (isLog) {
                  final logVal = log(min) + v * (log(max) - log(min));
                  onChanged(exp(logVal));
                } else {
                  onChanged(min + v * (max - min));
                }
              } : null,
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: TextField(
            controller: controller,
            enabled: enabled,
            style: TextStyle(
                color: enabled ? Colors.white : Colors.white24,
                fontSize: 9, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              border: InputBorder.none,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            onSubmitted: onSubmit,
          ),
        ),
      ],
    );
  }
}

class _TypeSelector extends StatelessWidget {
  final FilterType selected;
  final bool enabled;
  final Function(FilterType) onChanged;
  const _TypeSelector({required this.selected, required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 3, runSpacing: 3,
      children: FilterType.values.map((t) => GestureDetector(
        onTap: enabled ? () => onChanged(t) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected == t
                  ? (enabled ? Colors.white : Colors.white38)
                  : Colors.white12,
              width: 0.5,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(t.label,
              style: TextStyle(
                color: selected == t
                    ? (enabled ? Colors.white : Colors.white38)
                    : Colors.white24,
                fontSize: 7, letterSpacing: 0.5,
              )),
        ),
      )).toList(),
    );
  }
}
