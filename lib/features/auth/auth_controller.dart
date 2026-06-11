import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../core/api_service.dart';

class AuthState {
  final bool isLoggedIn;
  final bool isLoading;
  final String? error;
  final int? userId;
  final String? email;
  final String? nickname;

  const AuthState({
    this.isLoggedIn = false,
    this.isLoading = false,
    this.error,
    this.userId,
    this.email,
    this.nickname,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    bool? isLoading,
    String? error,
    int? userId,
    String? email,
    String? nickname,
  }) => AuthState(
    isLoggedIn: isLoggedIn ?? this.isLoggedIn,
    isLoading: isLoading ?? this.isLoading,
    error: error,
    userId: userId ?? this.userId,
    email: email ?? this.email,
    nickname: nickname ?? this.nickname,
  );
}

final authProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(),
);

class AuthController extends StateNotifier<AuthState> {
  AuthController() : super(const AuthState()) {
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final user = await ApiService.getUser();
    final token = await ApiService.getToken();
    if (user != null && token != null) {
      state = state.copyWith(
        isLoggedIn: true,
        userId: user['id'],
        email: user['email'],
        nickname: user['nickname'],
      );
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true);
    final res = await ApiService.login(email, password);
    if (res['status'] == 'ok') {
      final data = res['data'];
      await ApiService.saveToken(data['token']);
      await ApiService.saveUser(data['id'], data['email'], data['nickname']);
      state = state.copyWith(
        isLoggedIn: true,
        isLoading: false,
        userId: data['id'],
        email: data['email'],
        nickname: data['nickname'],
      );
      return true;
    } else {
      state = state.copyWith(isLoading: false, error: res['message']);
      return false;
    }
  }

  Future<bool> register(String email, String password, String nickname) async {
    state = state.copyWith(isLoading: true);
    final res = await ApiService.register(email, password, nickname);
    if (res['status'] == 'ok') {
      final data = res['data'];
      await ApiService.saveToken(data['token']);
      await ApiService.saveUser(data['id'], data['email'], nickname);
      state = state.copyWith(
        isLoggedIn: true,
        isLoading: false,
        userId: data['id'],
        email: data['email'],
        nickname: nickname,
      );
      return true;
    } else {
      state = state.copyWith(isLoading: false, error: res['message']);
      return false;
    }
  }



  Future<bool> loginWithGoogle() async {
    try {
      await GoogleSignIn.instance.initialize();
      final response = await GoogleSignIn.instance.authenticate();
      if (response == null) return false;
      final email = response.email;
      final nickname = response.displayName ?? email.split('@')[0];
      final googleId = response.id;
      final res = await ApiService.loginWithSocial(
        provider: 'google',
        providerId: googleId,
        email: email,
        nickname: nickname,
      );

      if (res['status'] == 'ok') {
        final data = res['data'];
        await ApiService.saveToken(data['token']);
        await ApiService.saveUser(data['id'], data['email'], data['nickname']);
        state = state.copyWith(
          isLoggedIn: true,
          email: data['email'],
          nickname: data['nickname'],
        );
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> loginWithApple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final email = credential.email ?? 'apple_\${credential.userIdentifier}@apple.com';
      final nickname = [
        credential.givenName,
        credential.familyName,
      ].where((s) => s != null && s.isNotEmpty).join(' ');

      final res = await ApiService.loginWithSocial(
        provider: 'apple',
        providerId: credential.userIdentifier ?? email,
        email: email,
        nickname: nickname.isNotEmpty ? nickname : email.split('@')[0],
      );

      if (res['status'] == 'ok') {
        final data = res['data'];
        await ApiService.saveToken(data['token']);
        await ApiService.saveUser(data['id'], data['email'], data['nickname']);
        state = state.copyWith(
          isLoggedIn: true,
          email: data['email'],
          nickname: data['nickname'],
        );
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
  Future<bool> loginWithKakao() async {
    try {
      const kakaoKey = 'b9ecf65d6b446e6f1e5b3b40f86425e6';
      const redirectUri = 'tunai://kakao/oauth';
      final authUrl = Uri.https('kauth.kakao.com', '/oauth/authorize', {
        'client_id': kakaoKey,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'profile_nickname,account_email',
      });
      final result = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: 'tunai',
      );
      final code = Uri.parse(result).queryParameters['code'];
      if (code == null) return false;
      final res = await ApiService.kakaoCallback(code: code, redirectUri: redirectUri);
      if (res['status'] == 'ok') {
        final data = res['data'];
        await ApiService.saveToken(data['token']);
        await ApiService.saveUser(data['id'], data['email'], data['nickname']);
        state = state.copyWith(
          isLoggedIn: true,
          email: data['email'],
          nickname: data['nickname'],
        );
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
  Future<void> logout() async {
    await ApiService.clearAuth();
    state = const AuthState();
  }
}
