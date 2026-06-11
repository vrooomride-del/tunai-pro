import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/speaker_profile.dart';

class SpeakerProfileSelector extends StatefulWidget {
  final void Function(SpeakerProfileState) onSelected;
  const SpeakerProfileSelector({super.key, required this.onSelected});
  @override
  State<SpeakerProfileSelector> createState() => _SpeakerProfileSelectorState();
}

class _SpeakerProfileSelectorState extends State<SpeakerProfileSelector> {
  SpeakerProfileMode _mode = SpeakerProfileMode.skip;
  final _selectedBuiltin = kTunaiOneProfile;
  final _fsCtrl = TextEditingController(text: '80');
  final _qtsCtrl = TextEditingController(text: '0.40');
  final _vasCtrl = TextEditingController(text: '5.0');
  final _xmaxCtrl = TextEditingController(text: '5.0');
  final _sensCtrl = TextEditingController(text: '87.0');
  final _volCtrl = TextEditingController();
  final _portLCtrl = TextEditingController();
  final _portDCtrl = TextEditingController();

  @override
  void dispose() {
    for (final c in [_fsCtrl,_qtsCtrl,_vasCtrl,_xmaxCtrl,_sensCtrl,_volCtrl,_portLCtrl,_portDCtrl]) c.dispose();
    super.dispose();
  }

  SpeakerProfileState _buildState() {
    if (_mode == SpeakerProfileMode.builtin)
      return SpeakerProfileState(mode: _mode, selectedProfile: _selectedBuiltin);
    if (_mode == SpeakerProfileMode.custom) {
      final custom = SpeakerProfile(
        id: 'custom', name: '직접 입력', description: '사용자 정의 스피커',
        fs: double.tryParse(_fsCtrl.text) ?? 80,
        qts: double.tryParse(_qtsCtrl.text) ?? 0.4,
        vas: double.tryParse(_vasCtrl.text) ?? 5.0,
        xmax: double.tryParse(_xmaxCtrl.text) ?? 5.0,
        sensitivity: double.tryParse(_sensCtrl.text) ?? 87.0,
        enclosureVolume: double.tryParse(_volCtrl.text),
        portLength: double.tryParse(_portLCtrl.text),
        portDiameter: double.tryParse(_portDCtrl.text),
      );
      return SpeakerProfileState(mode: _mode, customProfile: custom);
    }
    return const SpeakerProfileState(mode: SpeakerProfileMode.skip);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('SPEAKER PROFILE', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 3)),
          const SizedBox(height: 4),
          const Text('T/S 파라미터를 선택하면 AI가 물리 제약을 반영해 튜닝합니다.', style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 20),
          _ModeCard(title: 'TUNAI One', subtitle: 'Fs 75Hz · Qts 0.38 · Xmax 4.5mm · 87dB', selected: _mode == SpeakerProfileMode.builtin, icon: Icons.speaker, onTap: () => setState(() => _mode = SpeakerProfileMode.builtin)),
          const SizedBox(height: 8),
          _ModeCard(title: '직접 입력', subtitle: 'T/S 파라미터 수동 입력', selected: _mode == SpeakerProfileMode.custom, icon: Icons.tune, onTap: () => setState(() => _mode = SpeakerProfileMode.custom)),
          const SizedBox(height: 8),
          _ModeCard(title: '스킵', subtitle: 'FRD 측정 데이터만으로 튜닝', selected: _mode == SpeakerProfileMode.skip, icon: Icons.skip_next, onTap: () => setState(() => _mode = SpeakerProfileMode.skip)),
          if (_mode == SpeakerProfileMode.custom) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 12),
            const Text('T/S PARAMETERS', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _TsField(label: 'Fs (Hz)', ctrl: _fsCtrl)),
              const SizedBox(width: 8),
              Expanded(child: _TsField(label: 'Qts', ctrl: _qtsCtrl)),
              const SizedBox(width: 8),
              Expanded(child: _TsField(label: 'Vas (L)', ctrl: _vasCtrl)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _TsField(label: 'Xmax (mm)', ctrl: _xmaxCtrl)),
              const SizedBox(width: 8),
              Expanded(child: _TsField(label: '감도 (dB)', ctrl: _sensCtrl)),
              const SizedBox(width: 8),
              Expanded(child: _TsField(label: '체적 (L)', ctrl: _volCtrl, required: false)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _TsField(label: '포트 길이 (mm)', ctrl: _portLCtrl, required: false)),
              const SizedBox(width: 8),
              Expanded(child: _TsField(label: '포트 직경 (mm)', ctrl: _portDCtrl, required: false)),
              const Expanded(child: SizedBox()),
            ]),
          ],
          if (_mode == SpeakerProfileMode.builtin) ...[
            const SizedBox(height: 16),
            _ProfileInfo(profile: _selectedBuiltin),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => widget.onSelected(_buildState()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white, foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: Text(_mode == SpeakerProfileMode.skip ? '프로파일 없이 측정 시작' : '이 프로파일로 측정 시작',
                style: const TextStyle(fontSize: 12, letterSpacing: 2)),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title, subtitle;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;
  const _ModeCard({required this.title, required this.subtitle, required this.selected, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: selected ? Colors.white : Colors.white12),
        borderRadius: BorderRadius.circular(6),
        color: selected ? Colors.white.withOpacity(0.05) : Colors.transparent,
      ),
      child: Row(children: [
        Icon(icon, color: selected ? Colors.white : Colors.white30, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: selected ? Colors.white : Colors.white54, fontSize: 12, letterSpacing: 1.5)),
          Text(subtitle, style: const TextStyle(color: Colors.white30, fontSize: 10)),
        ])),
        if (selected) const Icon(Icons.check, color: Colors.white, size: 14),
      ]),
    ),
  );
}

class _TsField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final bool required;
  const _TsField({required this.label, required this.ctrl, this.required = true});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(color: required ? Colors.white38 : Colors.white24, fontSize: 9, letterSpacing: 1)),
      const SizedBox(height: 4),
      TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
        style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: required ? Colors.white24 : Colors.white12), borderRadius: BorderRadius.circular(4)),
          focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white54), borderRadius: BorderRadius.circular(4)),
          hintText: required ? '' : '선택', hintStyle: const TextStyle(color: Colors.white12, fontSize: 10),
        ),
      ),
    ],
  );
}

class _ProfileInfo extends StatelessWidget {
  final SpeakerProfile profile;
  const _ProfileInfo({required this.profile});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(6), color: Colors.white.withOpacity(0.03)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('DSP 안전 범위 (자동 적용)', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.5)),
      const SizedBox(height: 8),
      _InfoRow('HPF 권장', '${profile.recommendedHpfFreq.toStringAsFixed(0)} Hz'),
      _InfoRow('최대 저역 부스트', '${profile.maxBassBoostDb.toStringAsFixed(1)} dB'),
      _InfoRow('감도 기준 오프셋', '${profile.gainReferenceOffset >= 0 ? '+' : ''}${profile.gainReferenceOffset.toStringAsFixed(1)} dB'),
    ]),
  );
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      Text(value, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500)),
    ]),
  );
}
