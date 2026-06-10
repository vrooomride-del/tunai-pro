import 'dart:math';
import 'package:flutter/material.dart';
import '../dsp_state.dart';

class CrossoverEditor extends StatelessWidget {
  final CrossoverFilter hpFilter;
  final CrossoverFilter lpFilter;
  final Function(CrossoverFilter) onHpChanged;
  final Function(CrossoverFilter) onLpChanged;

  const CrossoverEditor({
    super.key,
    required this.hpFilter,
    required this.lpFilter,
    required this.onHpChanged,
    required this.onLpChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _CrossoverSide(label: 'HP', filter: hpFilter, onChanged: onHpChanged)),
        const SizedBox(width: 8),
        Expanded(child: _CrossoverSide(label: 'LP', filter: lpFilter, onChanged: onLpChanged)),
      ],
    );
  }
}

class _CrossoverSide extends StatefulWidget {
  final String label;
  final CrossoverFilter filter;
  final Function(CrossoverFilter) onChanged;
  const _CrossoverSide({required this.label, required this.filter, required this.onChanged});

  @override
  State<_CrossoverSide> createState() => _CrossoverSideState();
}

class _CrossoverSideState extends State<_CrossoverSide> {
  late TextEditingController _freqCtrl;

  @override
  void initState() {
    super.initState();
    _freqCtrl = TextEditingController(text: widget.filter.frequency.toStringAsFixed(0));
  }

  @override
  void didUpdateWidget(_CrossoverSide old) {
    super.didUpdateWidget(old);
    if (old.filter.frequency != widget.filter.frequency)
      _freqCtrl.text = widget.filter.frequency.toStringAsFixed(0);
  }

  @override
  void dispose() { _freqCtrl.dispose(); super.dispose(); }

  double _logNorm(double v) => (log(v) - log(20)) / (log(20000) - log(20));
  double _logDenorm(double v) => exp(log(20) + v * (log(20000) - log(20)));

  @override
  Widget build(BuildContext context) {
    final f = widget.filter;
    final active = f.type != CrossoverType.bypass;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: active ? Colors.white24 : Colors.white12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label,
              style: TextStyle(
                color: active ? Colors.white : Colors.white38,
                fontSize: 9, letterSpacing: 3,
              )),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4, runSpacing: 4,
            children: CrossoverType.values.map((t) => GestureDetector(
              onTap: () => widget.onChanged(f.copyWith(type: t)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: f.type == t ? Colors.white : Colors.white12, width: 0.5),
                  borderRadius: BorderRadius.circular(2),
                  color: f.type == t ? Colors.white.withOpacity(0.05) : Colors.transparent,
                ),
                child: Text(t.label,
                    style: TextStyle(
                      color: f.type == t ? Colors.white : Colors.white24,
                      fontSize: 8, letterSpacing: 0.5,
                    )),
              ),
            )).toList(),
          ),
          if (active) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('FREQ',
                    style: TextStyle(color: Colors.white38, fontSize: 8, letterSpacing: 1)),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _freqCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      isDense: true,
                      suffix: Text('Hz', style: TextStyle(color: Colors.white38, fontSize: 9)),
                      contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24, width: 0.5)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white, width: 0.5)),
                    ),
                    keyboardType: TextInputType.number,
                    onSubmitted: (v) {
                      final freq = double.tryParse(v);
                      if (freq != null)
                        widget.onChanged(f.copyWith(frequency: freq.clamp(20, 20000)));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                trackHeight: 1,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: _logNorm(f.frequency).clamp(0.0, 1.0),
                onChanged: (v) => widget.onChanged(f.copyWith(frequency: _logDenorm(v))),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
