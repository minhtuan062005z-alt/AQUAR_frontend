import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
String get apiBaseUrl => configuredApiBaseUrl.isNotEmpty
    ? configuredApiBaseUrl
    : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:5080'
        : 'http://127.0.0.1:5080');

abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => storage.read(key: 'jwt');
  @override
  Future<void> write(String token) => storage.write(key: 'jwt', value: token);
  @override
  Future<void> clear() => storage.delete(key: 'jwt');
}

enum AuthEvent { expired, passwordRequired }

class Api {
  Api({Dio? client, TokenStore? tokens})
      : tokens = tokens ?? SecureTokenStore(),
        dio = client ??
            Dio(
              BaseOptions(
                baseUrl: apiBaseUrl,
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 15),
              ),
            ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            if (options.path != '/api/auth/login') {
              final token = await this.tokens.read();
              if (token != null) {
                options.headers['Authorization'] = 'Bearer $token';
              }
            }
            handler.next(options);
          } catch (_) {
            handler.reject(
              DioException(
                requestOptions: options,
                error: 'Không đọc được phiên đăng nhập an toàn.',
              ),
            );
          }
        },
        onError: (error, handler) async {
          try {
            if (error.requestOptions.path != '/api/auth/login') {
              final token = await this.tokens.read();
              // Ignore errors from a request belonging to an older session.
              if (token != null &&
                  error.requestOptions.headers['Authorization'] ==
                      'Bearer $token') {
                if (error.response?.statusCode == 401) {
                  await logout();
                  authEvent.value = AuthEvent.expired;
                } else if (error.response?.statusCode == 403 &&
                    error.response?.data is Map &&
                    error.response?.data['code'] == 'MUST_CHANGE_PASSWORD') {
                  authEvent.value = AuthEvent.passwordRequired;
                }
              }
            }
          } catch (_) {
            // Preserve the original HTTP error if secure storage is unavailable.
          }
          handler.next(error);
        },
      ),
    );
  }
  static final Api instance = Api();
  final TokenStore tokens;
  final Dio dio;
  final authEvent = ValueNotifier<AuthEvent?>(null);
  Future<void> logout() async {
    await tokens.clear();
    authEvent.value = null;
  }
}

String errorText(Object e, {bool login = false}) {
  if (e is FormatException) return e.message;
  if (e is DioException) {
    final code = e.response?.statusCode;
    if (code == 401) {
      return login
          ? 'Email hoặc mật khẩu không đúng, hoặc tài khoản đã bị khóa.'
          : 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
    }
    if (code == 403) {
      final data = e.response?.data;
      if (data is Map && data['code'] == 'MUST_CHANGE_PASSWORD') {
        return 'Bạn phải đổi mật khẩu trước khi sử dụng ứng dụng.';
      }
      return 'Bạn không có quyền thực hiện thao tác này.';
    }
    if (code == 429) {
      return 'Đăng nhập quá nhiều lần. Vui lòng chờ một phút rồi thử lại.';
    }
    final data = e.response?.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    if (data is Map && data['errors'] is Map) {
      for (final value in (data['errors'] as Map).values) {
        if (value is List && value.isNotEmpty && value.first is String) {
          return value.first as String;
        }
      }
      return 'Thông tin không hợp lệ. Kiểm tra lại các trường đã nhập.';
    }
    if (code == 409) {
      return 'Dữ liệu bị trùng hoặc vừa thay đổi. Vui lòng tải lại.';
    }
    if (code != null) return 'Máy chủ trả về lỗi HTTP $code.';
    return 'Không kết nối được API. Kiểm tra mạng và địa chỉ máy chủ.';
  }
  return 'Không thể hoàn tất thao tác. Vui lòng thử lại.';
}
