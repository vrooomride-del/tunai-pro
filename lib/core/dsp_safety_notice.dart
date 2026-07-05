import 'package:flutter/material.dart';

/// Safety Validation Layer가 값을 clamp했을 때 사용자에게 알리는 전역 채널.
/// 어댑터/컨트롤러처럼 BuildContext가 없는 코드에서도 호출할 수 있도록
/// 전역 [GlobalKey]를 통해 스낵바를 띄운다 — 조용히 값만 바꾸고 넘어가지 않기 위함.
class DspSafetyNotice {
  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  static void show(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('⚠️ $message'),
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xFF2A2A00),
      ),
    );
  }
}
