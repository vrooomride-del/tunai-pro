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

  static Future<Map<String, dynamic>> register(String email, String password, String nickname) async {
    try {
      final res = await _dio.post('/auth/register',
          data: {'email': email, 'password': password, 'nickname': nickname});
      return res.data;
    } on DioException catch (e) { return {'status': 'error', 'message': e.message}; }
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final res = await _dio.post('/auth/login',
          data: {'email': email, 'password': password});
      return res.data;
    } on DioException catch (e) { return {'status': 'error', 'message': e.message}; }
  }

  static Future<Map<String, dynamic>> saveMeasurement({
    required List<Map<String, dynamic>> peaks,
    required List<Map<String, dynamic>> fps,
    required List<Map<String, dynamic>> scms,
  }) async {
    try {
      final opts = await _authOptions();
      final res = await _dio.post('/measurements',
          data: {'peaks_json': peaks, 'fps_json': fps, 'scms_json': scms},
          options: opts);
      return res.data;
    } on DioException catch (e) { return {'status': 'error', 'message': e.message}; }
  }

  static Future<Map<String, dynamic>> getPresets({String? hash}) async {
    try {
      final res = await _dio.get('/presets',
          queryParameters: hash != null ? {'hash': hash} : null);
      return res.data;
    } on DioException catch (e) { return {'status': 'error', 'message': e.message}; }
  }

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
        'title': title, 'description': description, 'fps_json': fps,
        'room_tag': roomTag, 'enclosure_hash': enclosureHash,
        'price': price, 'is_public': 1,
      }, options: opts);
      return res.data;
    } on DioException catch (e) { return {'status': 'error', 'message': e.message}; }
  }

  static Future<Map<String, dynamic>> getMeasurements() async {
    try {
      final opts = await _authOptions();
      final res = await _dio.get('/measurements', options: opts);
      return res.data;
    } catch (e) { return {'status': 'error', 'message': e.toString()}; }
  }

  static Future<Map<String, dynamic>> likePreset(int id) async {
    try {
      final opts = await _authOptions();
      final res = await _dio.post('/community/like/$id', options: opts);
      return res.data;
    } catch (e) { return {'status': 'error', 'message': e.toString()}; }
  }

  static Future<Map<String, dynamic>> getComments(int id) async {
    try {
      final res = await _dio.get('/community/comments/$id');
      return res.data;
    } catch (e) { return {'status': 'error', 'message': e.toString()}; }
  }

  static Future<Map<String, dynamic>> addComment(int id, String content) async {
    try {
      final opts = await _authOptions();
      final res = await _dio.post('/community/comment/$id',
          data: {'content': content}, options: opts);
      return res.data;
    } catch (e) { return {'status': 'error', 'message': e.toString()}; }
  }

  static Future<Map<String, dynamic>> getTrending() async {
    try {
      final res = await _dio.get('/community/trending');
      return res.data;
    } catch (e) { return {'status': 'error', 'message': e.toString()}; }
  }

  static Future<Map<String, dynamic>> getPosts({String category = 'all', int page = 1}) async {
    try {
      final res = await _dio.get('/posts',
          queryParameters: {'category': category, 'page': page});
      return res.data;
    } catch (e) { return {'status': 'error', 'message': e.toString()}; }
  }

  static Future<Map<String, dynamic>> getPost(int id) async {
    try {
      final res = await _dio.get('/posts/$id');
      return res.data;
    } catch (e) { return {'status': 'error', 'message': e.toString()}; }
  }

  static Future<Map<String, dynamic>> createPost({
    required String title, required String content, required String category,
  }) async {
    try {
      final opts = await _authOptions();
      final res = await _dio.post('/posts',
          data: {'title': title, 'content': content, 'category': category},
          options: opts);
      return res.data;
    } catch (e) { return {'status': 'error', 'message': e.toString()}; }
  }

  static Future<Map<String, dynamic>> addPostComment(int id, String content) async {
    try {
      final opts = await _authOptions();
      final res = await _dio.post('/posts/$id/comment',
          data: {'content': content}, options: opts);
      return res.data;
    } catch (e) { return {'status': 'error', 'message': e.toString()}; }
  }

  static Future<Map<String, dynamic>> likePost(int id) async {
    try {
      final opts = await _authOptions();
      final res = await _dio.post('/posts/$id/like', options: opts);
      return res.data;
    } catch (e) { return {'status': 'error', 'message': e.toString()}; }
  }
  static Future<Map<String, dynamic>> kakaoCallback({
    required String code,
    required String redirectUri,
  }) async {
    try {
      final res = await _dio.post('/auth/kakao-callback', data: {
        'code': code,
        'redirect_uri': redirectUri,
      });
      return res.data;
    } catch (e) { return {'status': 'error', 'message': e.toString()}; }
  }

  static Future<Map<String, dynamic>> loginWithSocial({
    required String provider,
    required String providerId,
    required String email,
    required String nickname,
  }) async {
    try {
      final res = await _dio.post('/auth/social', data: {
        'provider': provider,
        'provider_id': providerId,
        'email': email,
        'nickname': nickname,
      });
      return res.data;
    } catch (e) { return {'status': 'error', 'message': e.toString()}; }
  }

}