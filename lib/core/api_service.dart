import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'https://api.tunai.kr';
  static final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'Content-Type': 'application/json'},
  ));

  // 토큰 저장/조회
  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Future<void> saveUser(int id, String email, String nickname) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_id', id);
    await prefs.setString('user_email', email);
    await prefs.setString('user_nickname', nickname);
  }

  static Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('user_id');
    if (id == null) return null;
    return {
      'id': id,
      'email': prefs.getString('user_email') ?? '',
      'nickname': prefs.getString('user_nickname') ?? '',
    };
  }

  static Future<void> clearAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_id');
    await prefs.remove('user_email');
    await prefs.remove('user_nickname');
  }

  static Future<Options> _authOptions() async {
    final token = await getToken();
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  // 회원가입
  static Future<Map<String, dynamic>> register(String email, String password, String nickname) async {
    try {
      final res = await _dio.post('/auth/register', data: {
        'email': email,
        'password': password,
        'nickname': nickname,
      });
      return res.data;
    } on DioException catch (e) {
      return {'status': 'error', 'message': e.message};
    }
  }

  // 로그인
  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final res = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      return res.data;
    } on DioException catch (e) {
      return {'status': 'error', 'message': e.message};
    }
  }

  // 측정 저장
  static Future<Map<String, dynamic>> saveMeasurement({
    required List<Map<String, dynamic>> peaks,
    required List<Map<String, dynamic>> fps,
    required List<Map<String, dynamic>> scms,
  }) async {
    try {
      final opts = await _authOptions();
      final res = await _dio.post('/measurements', data: {
        'peaks_json': peaks,
        'fps_json': fps,
        'scms_json': scms,
      }, options: opts);
      return res.data;
    } on DioException catch (e) {
      return {'status': 'error', 'message': e.message};
    }
  }

  // 프리셋 목록
  static Future<Map<String, dynamic>> getPresets({String? hash}) async {
    try {
      final res = await _dio.get('/presets',
          queryParameters: hash != null ? {'hash': hash} : null);
      return res.data;
    } on DioException catch (e) {
      return {'status': 'error', 'message': e.message};
    }
  }

  // 프리셋 업로드
  static Future<Map<String, dynamic>> uploadPreset({
    required String title,
    required String? description,
    required List<Map<String, dynamic>> fps,
    String? roomTag,
    String? enclosureHash,
    int price = 0,
  }) async {
    try {
      final opts = await _authOptions();
      final res = await _dio.post('/presets', data: {
        'title': title,
        'description': description,
        'fps_json': fps,
        'room_tag': roomTag,
        'enclosure_hash': enclosureHash,
        'price': price,
        'is_public': 1,
      }, options: opts);
      return res.data;
    } on DioException catch (e) {
      return {'status': 'error', 'message': e.message};
    }
  }
}
