// ── TUNAI PRO Phase S — Demo Project Factory ──────────────────────────────────
// Creates a preloaded synthetic demo project for workstation demos.
// All data is clearly synthetic. Not measured production data.
// No hardware write. No USBi/BLE/SafeLoad/EEPROM. No real DSP addresses invented.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_project.dart';
import 'pro_acoustic_data.dart';
import 'pro_tuning_data.dart';
import 'pro_protection_data.dart';
import 'pro_export_data.dart';

const _kDemoNote = 'Demo data only. Not measured production data.';

// ── Synthetic FRD sample data ─────────────────────────────────────────────────

List<MeasurementDataPoint> _tweeterFrd() => const [
  MeasurementDataPoint(frequencyHz:  1000, magnitudeDb: 86.2, phaseDeg:  -12.0),
  MeasurementDataPoint(frequencyHz:  2000, magnitudeDb: 88.0, phaseDeg:  -24.0),
  MeasurementDataPoint(frequencyHz:  3000, magnitudeDb: 89.1, phaseDeg:  -34.0),
  MeasurementDataPoint(frequencyHz:  5000, magnitudeDb: 90.3, phaseDeg:  -55.0),
  MeasurementDataPoint(frequencyHz:  7000, magnitudeDb: 90.8, phaseDeg:  -78.0),
  MeasurementDataPoint(frequencyHz: 10000, magnitudeDb: 90.1, phaseDeg: -102.0),
  MeasurementDataPoint(frequencyHz: 12000, magnitudeDb: 89.4, phaseDeg: -122.0),
  MeasurementDataPoint(frequencyHz: 15000, magnitudeDb: 88.2, phaseDeg: -145.0),
  MeasurementDataPoint(frequencyHz: 18000, magnitudeDb: 86.5, phaseDeg: -168.0),
  MeasurementDataPoint(frequencyHz: 20000, magnitudeDb: 84.0, phaseDeg:  175.0),
];

List<MeasurementDataPoint> _wooferFrd() => const [
  MeasurementDataPoint(frequencyHz:   50,  magnitudeDb: 80.5, phaseDeg:  12.0),
  MeasurementDataPoint(frequencyHz:  100,  magnitudeDb: 84.0, phaseDeg:   5.0),
  MeasurementDataPoint(frequencyHz:  200,  magnitudeDb: 87.5, phaseDeg:  -8.0),
  MeasurementDataPoint(frequencyHz:  500,  magnitudeDb: 88.2, phaseDeg: -22.0),
  MeasurementDataPoint(frequencyHz: 1000,  magnitudeDb: 87.8, phaseDeg: -38.0),
  MeasurementDataPoint(frequencyHz: 2000,  magnitudeDb: 86.0, phaseDeg: -58.0),
  MeasurementDataPoint(frequencyHz: 3000,  magnitudeDb: 83.0, phaseDeg: -82.0),
  MeasurementDataPoint(frequencyHz: 5000,  magnitudeDb: 78.5, phaseDeg: -115.0),
  MeasurementDataPoint(frequencyHz: 8000,  magnitudeDb: 72.0, phaseDeg: -148.0),
  MeasurementDataPoint(frequencyHz: 10000, magnitudeDb: 66.0, phaseDeg:  170.0),
];

List<MeasurementDataPoint> _wooferZma() => const [
  MeasurementDataPoint(frequencyHz:   20,  impedanceOhm: 7.4, impedancePhaseDeg: -5.0),
  MeasurementDataPoint(frequencyHz:   50,  impedanceOhm: 8.1, impedancePhaseDeg:  8.0),
  MeasurementDataPoint(frequencyHz:   80,  impedanceOhm:28.0, impedancePhaseDeg: 42.0),
  MeasurementDataPoint(frequencyHz:  100,  impedanceOhm:16.5, impedancePhaseDeg: 28.0),
  MeasurementDataPoint(frequencyHz:  200,  impedanceOhm: 7.8, impedancePhaseDeg:  4.0),
  MeasurementDataPoint(frequencyHz:  500,  impedanceOhm: 7.2, impedancePhaseDeg: -2.0),
  MeasurementDataPoint(frequencyHz: 1000,  impedanceOhm: 7.6, impedancePhaseDeg:  6.0),
  MeasurementDataPoint(frequencyHz: 2000,  impedanceOhm: 9.0, impedancePhaseDeg: 14.0),
  MeasurementDataPoint(frequencyHz: 5000,  impedanceOhm:12.5, impedancePhaseDeg: 22.0),
  MeasurementDataPoint(frequencyHz:10000,  impedanceOhm:18.0, impedancePhaseDeg: 30.0),
];

// ── Build demo ParsedMeasurementData ─────────────────────────────────────────

ParsedMeasurementData _parsedFrd(String id, String file, List<MeasurementDataPoint> pts) {
  final now = DateTime.now();
  return ParsedMeasurementData(
    id: id,
    sourceFileName: file,
    fileType: AcousticFileType.frd,
    importedAt: now,
    points: pts,
    notes: _kDemoNote,
  );
}

ParsedMeasurementData _parsedZma(String id, String file, List<MeasurementDataPoint> pts) {
  final now = DateTime.now();
  return ParsedMeasurementData(
    id: id,
    sourceFileName: file,
    fileType: AcousticFileType.zma,
    importedAt: now,
    points: pts,
    notes: _kDemoNote,
  );
}

AcousticFileRef _frdRef(String id, String file, int count) {
  final now = DateTime.now();
  return AcousticFileRef(
    id: id,
    fileName: file,
    type: AcousticFileType.frd,
    importedAt: now,
    pointCount: count,
    parseStatus: MeasurementParseStatus.parsed,
    parsedDataId: 'pd_$id',
    notes: _kDemoNote,
  );
}

AcousticFileRef _zmaRef(String id, String file, int count) {
  final now = DateTime.now();
  return AcousticFileRef(
    id: id,
    fileName: file,
    type: AcousticFileType.zma,
    importedAt: now,
    pointCount: count,
    parseStatus: MeasurementParseStatus.parsed,
    parsedDataId: 'pd_$id',
    notes: _kDemoNote,
  );
}

// ── Build demo DriverChannels ─────────────────────────────────────────────────

List<DriverChannel> _demoChanels() {
  final twFrdPts = _tweeterFrd();
  final wfFrdPts = _wooferFrd();
  final wfZmaPts = _wooferZma();

  final twFrdRefL = _frdRef('frd_tw_l', 'tweeter_L_demo.frd', twFrdPts.length);
  final twFrdRefR = _frdRef('frd_tw_r', 'tweeter_R_demo.frd', twFrdPts.length);
  final wfFrdRefL = _frdRef('frd_wf_l', 'woofer_L_demo.frd', wfFrdPts.length);
  final wfFrdRefR = _frdRef('frd_wf_r', 'woofer_R_demo.frd', wfFrdPts.length);
  final wfZmaRefL = _zmaRef('zma_wf_l', 'woofer_L_demo.zma', wfZmaPts.length);
  final wfZmaRefR = _zmaRef('zma_wf_r', 'woofer_R_demo.zma', wfZmaPts.length);

  final twFrdDataL = _parsedFrd('pd_frd_tw_l', 'tweeter_L_demo.frd', twFrdPts);
  final twFrdDataR = _parsedFrd('pd_frd_tw_r', 'tweeter_R_demo.frd', twFrdPts);
  final wfFrdDataL = _parsedFrd('pd_frd_wf_l', 'woofer_L_demo.frd', wfFrdPts);
  final wfFrdDataR = _parsedFrd('pd_frd_wf_r', 'woofer_R_demo.frd', wfFrdPts);
  final wfZmaDataL = _parsedZma('pd_zma_wf_l', 'woofer_L_demo.zma', wfZmaPts);
  final wfZmaDataR = _parsedZma('pd_zma_wf_r', 'woofer_R_demo.zma', wfZmaPts);

  return [
    DriverChannel(
      id: 'ch_tw_l',
      name: 'Tweeter L',
      role: DriverRole.coaxTweeter,
      side: DriverSide.left,
      dspOutputIndex: 1,
      frdFile: twFrdRefL,
      frdData: twFrdDataL,
      measurementStatus: MeasurementStatus.validated,
    ),
    DriverChannel(
      id: 'ch_wf_l',
      name: 'Woofer L',
      role: DriverRole.coaxWoofer,
      side: DriverSide.left,
      dspOutputIndex: 2,
      frdFile: wfFrdRefL,
      zmaFile: wfZmaRefL,
      frdData: wfFrdDataL,
      zmaData: wfZmaDataL,
      measurementStatus: MeasurementStatus.validated,
    ),
    DriverChannel(
      id: 'ch_tw_r',
      name: 'Tweeter R',
      role: DriverRole.coaxTweeter,
      side: DriverSide.right,
      dspOutputIndex: 3,
      frdFile: twFrdRefR,
      frdData: twFrdDataR,
      measurementStatus: MeasurementStatus.validated,
    ),
    DriverChannel(
      id: 'ch_wf_r',
      name: 'Woofer R',
      role: DriverRole.coaxWoofer,
      side: DriverSide.right,
      dspOutputIndex: 4,
      frdFile: wfFrdRefR,
      zmaFile: wfZmaRefR,
      frdData: wfFrdDataR,
      zmaData: wfZmaDataR,
      measurementStatus: MeasurementStatus.validated,
    ),
  ];
}

// ── Build demo TuningProjectState ─────────────────────────────────────────────

TuningProjectState _demoTuning() {
  // 2-way coax LR24 crossover at 2.5 kHz
  const xoFreq = 2500.0;
  const xoType = CrossoverFilterType.linkwitzRiley;
  const xoSlope = CrossoverSlope.db24;

  const peqChannels = [
    PeqChannelState(
      channelId: 'ch_wf_l',
      bands: [
        PeqBand(
          id: 'peq_wf_l_1',
          frequencyHz: 80.0,
          gainDb: 3.5,
          q: 1.2,
          note: 'Bass shelf lift — demo',
        ),
        PeqBand(
          id: 'peq_wf_l_2',
          frequencyHz: 350.0,
          gainDb: -2.0,
          q: 2.0,
          note: 'Upper-mid notch — demo',
        ),
      ],
    ),
    PeqChannelState(
      channelId: 'ch_wf_r',
      bands: [
        PeqBand(
          id: 'peq_wf_r_1',
          frequencyHz: 80.0,
          gainDb: 3.5,
          q: 1.2,
          note: 'Bass shelf lift — demo',
        ),
        PeqBand(
          id: 'peq_wf_r_2',
          frequencyHz: 350.0,
          gainDb: -2.0,
          q: 2.0,
          note: 'Upper-mid notch — demo',
        ),
      ],
    ),
    PeqChannelState(
      channelId: 'ch_tw_l',
      bands: [
        PeqBand(
          id: 'peq_tw_l_1',
          frequencyHz: 8000.0,
          gainDb: -1.5,
          q: 1.5,
          note: 'HF presence dip — demo',
        ),
      ],
    ),
    PeqChannelState(
      channelId: 'ch_tw_r',
      bands: [
        PeqBand(
          id: 'peq_tw_r_1',
          frequencyHz: 8000.0,
          gainDb: -1.5,
          q: 1.5,
          note: 'HF presence dip — demo',
        ),
      ],
    ),
  ];

  const crossoverChannels = [
    CrossoverChannelState(
      channelId: 'ch_tw_l',
      highPass: CrossoverFilter(
        side: FilterSide.highPass,
        type: xoType,
        slope: xoSlope,
        frequencyHz: xoFreq,
        note: 'LR24 HPF @ 2.5 kHz — demo',
      ),
    ),
    CrossoverChannelState(
      channelId: 'ch_tw_r',
      highPass: CrossoverFilter(
        side: FilterSide.highPass,
        type: xoType,
        slope: xoSlope,
        frequencyHz: xoFreq,
        note: 'LR24 HPF @ 2.5 kHz — demo',
      ),
    ),
    CrossoverChannelState(
      channelId: 'ch_wf_l',
      lowPass: CrossoverFilter(
        side: FilterSide.lowPass,
        type: xoType,
        slope: xoSlope,
        frequencyHz: xoFreq,
        note: 'LR24 LPF @ 2.5 kHz — demo',
      ),
    ),
    CrossoverChannelState(
      channelId: 'ch_wf_r',
      lowPass: CrossoverFilter(
        side: FilterSide.lowPass,
        type: xoType,
        slope: xoSlope,
        frequencyHz: xoFreq,
        note: 'LR24 LPF @ 2.5 kHz — demo',
      ),
    ),
  ];

  const channelControls = [
    ChannelControlState(channelId: 'ch_tw_l', gainDb: -1.0),
    ChannelControlState(channelId: 'ch_tw_r', gainDb: -1.0),
    ChannelControlState(channelId: 'ch_wf_l', delayMs: 0.18),
    ChannelControlState(channelId: 'ch_wf_r', delayMs: 0.18),
  ];

  return TuningProjectState(
    peqChannels: peqChannels,
    crossoverChannels: crossoverChannels,
    channelControls: channelControls,
    hasManualChanges: true,
    tuningRevision: 1,
    notes: _kDemoNote,
  );
}

// ── Build demo ProtectionProjectState ─────────────────────────────────────────

ProtectionProjectState _demoProtection() {
  return ProtectionProjectState.createDefault().copyWith(
    verificationStatus: VerificationStatus.passedWithWarnings,
    revision: 1,
  );
}

// ── Build demo ExportProjectState ─────────────────────────────────────────────

ExportProjectState _demoExport() {
  final now = DateTime.now();
  final pkg = DspExportPackage(
    id: 'demo_export_pkg_1',
    targetPlatform: DspTargetPlatform.adau1466,
    status: ExportStatus.draftReady,
    projectName: 'TUNAI ONE Coax Demo',
    notes: _kDemoNote,
  );
  return ExportProjectState(
    packages: [pkg],
    activePackageId: pkg.id,
    selectedTarget: DspTargetPlatform.adau1466,
    revision: 1,
    updatedAt: now,
  );
}

// ── Main factory function ─────────────────────────────────────────────────────

ProProject createTunaiProDemoProject() {
  final now = DateTime.now();
  final id = 'demo_${now.millisecondsSinceEpoch}';

  final acousticState = MeasurementProjectState(
    driverChannels: _demoChanels(),
    importedFiles: const [],
    targetCurve: const TargetCurveState(
      selectedPreset: TargetCurvePreset.warm,
      notes: _kDemoNote,
    ),
  );

  return ProProject(
    id: id,
    name: 'TUNAI ONE Coax Demo',
    speakerModel: 'TUNAI ONE',
    roomName: 'Demo Studio',
    createdAt: now,
    updatedAt: now,
    sampleRate: 48000,
    dspTarget: 'ADAU1466',
    channelConfig: '2-way stereo',
    profileStatus: ProfileStatus.tuned,
    notes: _kDemoNote,
    acousticState: acousticState,
    tuningState: _demoTuning(),
    protectionState: _demoProtection(),
    exportState: _demoExport(),
  );
}
