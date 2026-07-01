import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../dsp_state.dart';

class OutputChannelStrip extends StatefulWidget {
  final OutputChannel channel;
  final bool selected;
  final VoidCallback onSelect;
  final Function(double) onGainChanged;
  final Function(double) onDelayChanged;
  final VoidCallback onMuteToggle;
  final VoidCallback onPolarityToggle;

  const OutputChannelStrip({
    super.key,
    required this.channel,
    required this.selected,
    required this.onSelect,
    required this.onGainChanged,
    required this.onDelayChanged,
    required this.onMuteToggle,
    required this.onPolarityToggle,
  });

  @override
  State<OutputChannelStrip> createState() => _OutputChannelStripState();
}

class _OutputChannelStripState extends State<OutputChannelStrip> {
  late TextEditingController _gainCtrl;
  late TextEditingController _delayCtrl;

  @override
  void initState() {
    super.initState();
    _gainCtrl = TextEditingController(
        text: widget.channel.gainDb.toStringAsFixed(1));
    _delayCtrl = TextEditingController(
        text: widget.channel.delayMs.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(OutputChannelStrip old) {
    super.didUpdateWidget(old);
    if (old.channel.gainDb != widget.channel.gainDb) {
      _gainCtrl.text = widget.channel.gainDb.toStringAsFixed(1);
    }
    if (old.channel.delayMs != widget.channel.delayMs) {
      _delayCtrl.text = widget.channel.delayMs.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _gainCtrl.dispose(); _delayCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    final sel = widget.selected;

    return GestureDetector(
      onTap: widget.onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          border: Border.all(color: sel ? Colors.white54 : Colors.white12),
          borderRadius: BorderRadius.circular(6),
          color: sel ? Colors.white.withValues(alpha: 0.03) : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 채널명 + MUTE + POLARITY
            Row(
              children: [
                Expanded(
                  child: Text(ch.name,
                      style: TextStyle(
                        color: ch.muted ? Colors.white38 : Colors.white,
                        fontSize: 16,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                      )),
                ),
                _IconBtn(
                  label: 'Ø',
                  active: ch.polarity,
                  onTap: widget.onPolarityToggle,
                  tooltip: '위상 반전',
                ),
                const SizedBox(width: 6),
                _IconBtn(
                  label: 'M',
                  active: ch.muted,
                  activeColor: Colors.redAccent,
                  onTap: widget.onMuteToggle,
                  tooltip: '뮤트',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // GAIN (휠 ±0.1dB)
            _StripRow(
              label: 'GAIN',
              unit: 'dB',
              value: ch.gainDb,
              min: -40, max: 12,
              scrollStep: 0.1,
              controller: _gainCtrl,
              onChanged: widget.onGainChanged,
              onSubmit: (v) {
                final g = double.tryParse(v);
                if (g != null) widget.onGainChanged(g.clamp(-40, 12));
              },
            ),
            const SizedBox(height: 8),

            // DELAY (휠 ±0.01ms)
            _StripRow(
              label: 'DLY',
              unit: 'ms',
              value: ch.delayMs,
              min: 0, max: 100,
              decimals: 2,
              scrollStep: 0.01,
              controller: _delayCtrl,
              onChanged: widget.onDelayChanged,
              onSubmit: (v) {
                final d = double.tryParse(v);
                if (d != null) widget.onDelayChanged(d.clamp(0, 100));
              },
            ),
            const SizedBox(height: 8),

            // 크로스오버 요약
            Wrap(
              spacing: 4, runSpacing: 4,
              children: [
                _XoChip('HP', ch.hpFilter),
                _XoChip('LP', ch.lpFilter),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  final String tooltip;

  const _IconBtn({
    required this.label,
    required this.active,
    required this.onTap,
    required this.tooltip,
    this.activeColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            border: Border.all(
                color: active ? activeColor : Colors.white38, width: 0.5),
            borderRadius: BorderRadius.circular(3),
            color: active ? activeColor.withValues(alpha: 0.15) : Colors.transparent,
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                  color: active ? activeColor : Colors.white38,
                  fontSize: 13, letterSpacing: 0.5,
                )),
          ),
        ),
      ),
    );
  }
}

class _StripRow extends StatelessWidget {
  final String label;
  final String unit;
  final double value;
  final double min, max;
  final TextEditingController controller;
  final int decimals;
  final double scrollStep;
  final Function(double) onChanged;
  final Function(String) onSubmit;

  const _StripRow({
    required this.label, required this.unit,
    required this.value, required this.min, required this.max,
    required this.controller, required this.onChanged, required this.onSubmit,
    this.decimals = 1, this.scrollStep = 0.1,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 44,
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white60, fontSize: 13, letterSpacing: 1))),
        Expanded(
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                final dir = event.scrollDelta.dy > 0 ? -1.0 : 1.0;
                onChanged((value + dir * scrollStep).clamp(min, max));
              }
            },
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                trackHeight: 2,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: ((value - min) / (max - min)).clamp(0.0, 1.0),
                onChanged: (v) => onChanged(min + v * (max - min)),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 58,
          child: TextField(
            controller: controller,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              isDense: true,
              suffix: Text(unit,
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              border: InputBorder.none,
            ),
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            onSubmitted: onSubmit,
          ),
        ),
      ],
    );
  }
}

class _XoChip extends StatelessWidget {
  final String label;
  final CrossoverFilter filter;
  const _XoChip(this.label, this.filter);

  @override
  Widget build(BuildContext context) {
    final active = filter.type != CrossoverType.bypass;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(
            color: active ? Colors.white38 : Colors.white12, width: 0.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        active
            ? '$label ${filter.type.label} ${filter.frequency.toStringAsFixed(0)}Hz'
            : '$label BYP',
        style: TextStyle(
          color: active ? Colors.white70 : Colors.white38,
          fontSize: 12, letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class InputChannelStrip extends StatefulWidget {
  final InputChannel channel;
  final bool selected;
  final VoidCallback onSelect;
  final Function(double) onGainChanged;

  const InputChannelStrip({
    super.key,
    required this.channel,
    required this.selected,
    required this.onSelect,
    required this.onGainChanged,
  });

  @override
  State<InputChannelStrip> createState() => _InputChannelStripState();
}

class _InputChannelStripState extends State<InputChannelStrip> {
  late TextEditingController _gainCtrl;

  @override
  void initState() {
    super.initState();
    _gainCtrl = TextEditingController(
        text: widget.channel.gainDb.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(InputChannelStrip old) {
    super.didUpdateWidget(old);
    if (old.channel.gainDb != widget.channel.gainDb) {
      _gainCtrl.text = widget.channel.gainDb.toStringAsFixed(1);
    }
  }

  @override
  void dispose() { _gainCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    final sel = widget.selected;

    return GestureDetector(
      onTap: widget.onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: sel ? Colors.white54 : Colors.white12),
          borderRadius: BorderRadius.circular(6),
          color: sel ? Colors.white.withValues(alpha: 0.03) : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ch.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _StripRow(
              label: 'GAIN', unit: 'dB',
              value: ch.gainDb, min: -40, max: 12,
              controller: _gainCtrl,
              onChanged: widget.onGainChanged,
              onSubmit: (v) {
                final g = double.tryParse(v);
                if (g != null) widget.onGainChanged(g.clamp(-40, 12));
              },
            ),
          ],
        ),
      ),
    );
  }
}
