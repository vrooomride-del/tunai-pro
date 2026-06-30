import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 출력 채널 쌍별 L/R 링크 상태 (기본값: 모두 ON)
///
/// 6개 출력 채널: TWE L(0) R(1) / MID L(2) R(3) / WOO L(4) R(5)
/// links[0] = TWE 링크, links[1] = MID 링크, links[2] = WOO 링크
final channelLinkProvider =
    StateProvider<List<bool>>((ref) => [true, true, true]);

/// 채널 인덱스(0-5)의 L/R 페어 인덱스 반환
/// 짝수(L) → 홀수(R), 홀수(R) → 짝수(L)
int channelPairOf(int idx) => idx.isEven ? idx + 1 : idx - 1;

/// 채널 인덱스(0-5)의 링크 그룹 인덱스 (0=TWE, 1=MID, 2=WOO)
int channelGroupOf(int idx) => idx ~/ 2;

/// 링크 상태 확인 헬퍼
bool isChannelLinked(List<bool> links, int idx) {
  final group = channelGroupOf(idx);
  return group < links.length && links[group];
}
