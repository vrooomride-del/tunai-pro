import '../../core/frd_parser.dart';

enum BoxType { sealed, ported, passiveRadiator }
enum DriverRole { fullrange, woofer, midrange, tweeter }

class DriverProfile {
  final String id;
  final String name;
  final DriverRole role;
  final TsParameters? tsParams;
  final List<FrdPoint> frdData;
  final List<ZmaPoint> zmaData;
  final bool fromFile;
  final String? fileName;
  final double? sensitivity;
  final double? recommendedXover;

  const DriverProfile({
    required this.id, required this.name, required this.role,
    this.tsParams, this.frdData = const [], this.zmaData = const [],
    this.fromFile = false, this.fileName, this.sensitivity, this.recommendedXover,
  });

  DriverProfile copyWith({
    TsParameters? tsParams, List<FrdPoint>? frdData, List<ZmaPoint>? zmaData,
    bool? fromFile, String? fileName, double? sensitivity, double? recommendedXover,
  }) => DriverProfile(
    id: id, name: name, role: role,
    tsParams: tsParams ?? this.tsParams,
    frdData: frdData ?? this.frdData,
    zmaData: zmaData ?? this.zmaData,
    fromFile: fromFile ?? this.fromFile,
    fileName: fileName ?? this.fileName,
    sensitivity: sensitivity ?? this.sensitivity,
    recommendedXover: recommendedXover ?? this.recommendedXover,
  );

  bool get hasFrd => frdData.isNotEmpty;
  bool get hasZma => zmaData.isNotEmpty;
  bool get hasTs => tsParams != null;
}

class EnclosureConfig {
  final BoxType type;
  final double volume;
  final double? portLength;
  final double? portDiameter;
  final double? portCount;

  const EnclosureConfig({
    required this.type, required this.volume,
    this.portLength, this.portDiameter, this.portCount,
  });

  double? get portResonance {
    if (type != BoxType.ported) return null;
    if (portLength == null || portDiameter == null) return null;
    final r = portDiameter! / 2 / 1000;
    final l = portLength! / 1000;
    final vb = volume / 1000;
    final area = 3.14159 * r * r;
    return (343.0 / (2 * 3.14159)) * (area / (l * vb)).clamp(0, 1e6);
  }
}

class SystemConfig {
  final List<DriverProfile> drivers;
  final EnclosureConfig? enclosure;
  final double? crossoverFrequency;
  final String? crossoverType;

  const SystemConfig({
    this.drivers = const [], this.enclosure,
    this.crossoverFrequency, this.crossoverType,
  });

  SystemConfig copyWith({
    List<DriverProfile>? drivers, EnclosureConfig? enclosure,
    double? crossoverFrequency, String? crossoverType,
  }) => SystemConfig(
    drivers: drivers ?? this.drivers,
    enclosure: enclosure ?? this.enclosure,
    crossoverFrequency: crossoverFrequency ?? this.crossoverFrequency,
    crossoverType: crossoverType ?? this.crossoverType,
  );

  Map<String, dynamic> toPromptMap() => {
    'drivers': drivers.map((d) => {
      'name': d.name, 'role': d.role.name,
      if (d.tsParams != null) 'ts': {'fs': d.tsParams!.fs, 'qts': d.tsParams!.qts, 're': d.tsParams!.re},
      if (d.sensitivity != null) 'sensitivity_db': d.sensitivity,
      if (d.recommendedXover != null) 'recommended_xover_hz': d.recommendedXover,
    }).toList(),
    if (enclosure != null) 'enclosure': {
      'type': enclosure!.type.name, 'volume_liters': enclosure!.volume,
      if (enclosure!.portLength != null) 'port_length_mm': enclosure!.portLength,
      if (enclosure!.portDiameter != null) 'port_diameter_mm': enclosure!.portDiameter,
      if (enclosure!.portResonance != null) 'port_resonance_hz': enclosure!.portResonance!.toStringAsFixed(1),
    },
    if (crossoverFrequency != null) 'crossover_hz': crossoverFrequency,
    if (crossoverType != null) 'crossover_type': crossoverType,
  };
}
