import '../pro_acoustic_data.dart';

/// Optional listening-position FRD set. Repeat sweeps remain on DriverChannel
/// and are intentionally not represented here.
class ListeningPositionFrdSet {
  final String positionId;
  final String label;
  final Map<String, ParsedMeasurementData> channels;

  const ListeningPositionFrdSet({
    required this.positionId,
    required this.label,
    required this.channels,
  });
}
