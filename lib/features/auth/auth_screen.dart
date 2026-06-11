import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_controller.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _isLogin = true;
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),
              const Text('TUNAI',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 28,
                      fontWeight: FontWeight.w200, letterSpacing: 10)),
              const SizedBox(height: 8),
              Text(_isLogin ? 'SIGN IN' : 'CREATE ACCOUNT',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 4)),
              const SizedBox(height: 60),
              _Field(label: 'EMAIL', controller: _emailCtrl, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 16),
              if (!_isLogin) ...[
                _Field(label: 'NICKNAME', controller: _nicknameCtrl),
                const SizedBox(height: 16),
              ],
              _Field(label: 'PASSWORD', controller: _passwordCtrl, obscure: true),
              const SizedBox(height: 8),
              if (auth.error != null)
                Text(auth.error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    textAlign: TextAlign.center),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: auth.isLoading ? null : () async {
                  bool ok;
                  if (_isLogin) {
                    ok = await ref.read(authProvider.notifier)
                        .login(_emailCtrl.text.trim(), _passwordCtrl.text);
                  } else {
                    ok = await ref.read(authProvider.notifier)
                        .register(_emailCtrl.text.trim(), _passwordCtrl.text, _nicknameCtrl.text.trim());
                  }
                  if (ok && mounted) Navigator.of(context).pop();
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    border: Border.all(color: auth.isLoading ? Colors.white24 : Colors.white),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: auth.isLoading
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 1, color: Colors.white38))
                        : Text(_isLogin ? 'SIGN IN' : 'CREATE ACCOUNT',
                            style: const TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 3)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: const [
                  Expanded(child: Divider(color: Colors.white12)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('또는', style: TextStyle(color: Colors.white24, fontSize: 11)),
                  ),
                  Expanded(child: Divider(color: Colors.white12)),
                ],
              ),
              const SizedBox(height: 12),
              // 애플 로그인
              GestureDetector(
                onTap: () async {
                  final ok = await ref.read(authProvider.notifier).loginWithApple();
                  if (ok && mounted) Navigator.of(context).pop();
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.apple, color: Colors.white, size: 22),
                      SizedBox(width: 8),
                      Text('Apple로 로그인',
                          style: TextStyle(color: Colors.white,
                              fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 애플 로그인
              GestureDetector(
                onTap: () async {
                  final ok = await ref.read(authProvider.notifier).loginWithApple();
                  if (ok && mounted) Navigator.of(context).pop();
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.apple, color: Colors.white, size: 22),
                      SizedBox(width: 8),
                      Text('Apple로 로그인',
                          style: TextStyle(color: Colors.white,
                              fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 구글 로그인
              GestureDetector(
                onTap: () async {
                  final ok = await ref.read(authProvider.notifier).loginWithGoogle();
                  if (ok && mounted) Navigator.of(context).pop();
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.g_mobiledata, color: Colors.red, size: 28),
                      SizedBox(width: 8),
                      Text('Google로 로그인',
                          style: TextStyle(color: Colors.black87,
                              fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 카카오 로그인
              GestureDetector(
                onTap: () async {
                  final ok = await ref.read(authProvider.notifier).loginWithKakao();
                  if (ok && mounted) Navigator.of(context).pop();
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE500),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.chat_bubble, color: Color(0xFF3A1D1D), size: 18),
                      SizedBox(width: 8),
                      Text('카카오 로그인',
                          style: TextStyle(color: Color(0xFF3A1D1D),
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => setState(() => _isLogin = !_isLogin),
                child: Text(
                  _isLogin ? '계정이 없으신가요?  CREATE ACCOUNT' : '이미 계정이 있으신가요?  SIGN IN',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType? keyboardType;
  const _Field({required this.label, required this.controller, this.obscure = false, this.keyboardType});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 2)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
            contentPadding: EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ],
    );
  }
}
