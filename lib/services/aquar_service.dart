import '../core/api.dart';
import '../models/user.dart';
import '../models/attendance.dart';
import 'attendance_location.dart';
import '../models/staff_member.dart';

class AquarService {
  AquarService({Api? api}) : api = api ?? Api.instance;
  final Api api;
  Future<AquarUser> login(String email, String password) async {
    final r = await api.dio.post(
      '/api/auth/login',
      data: {'email': email.trim(), 'password': password},
    );
    final data = Map<String, dynamic>.from(r.data as Map);
    final token = data['token'];
    if (token is! String || token.trim().isEmpty) {
      throw const FormatException(
        'Máy chủ không trả về phiên đăng nhập hợp lệ.',
      );
    }
    final userData = Map<String, dynamic>.from(data['user'] as Map);
    userData['mustChangePassword'] = data['mustChangePassword'] == true ||
        userData['mustChangePassword'] == true ||
        userData['MustChangePassword'] == true;
    final user = AquarUser.fromJson(userData);
    await api.tokens.write(token);
    api.authEvent.value = null;
    return user;
  }

  Future<void> changePassword(
    String current,
    String next,
    String confirm,
  ) async {
    await api.dio.put(
      '/api/account/password',
      data: {
        'currentPassword': current,
        'newPassword': next,
        'confirmNewPassword': confirm,
      },
    );
    await api.logout();
  }

  Future<void> logout() async {
    try {
      await api.dio.post('/api/auth/logout');
    } on Object {
      /* Local sign-out remains available when the server is unreachable. */
    } finally {
      await api.logout();
    }
  }

  Future<List<Map<String, dynamic>>> staff() async {
    final r = await api.dio.get('/api/staff');
    return (r.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<StaffMember>> staffMembers() async =>
      (await staff()).map(StaffMember.fromJson).toList();

  Future<List<Map<String, dynamic>>> departments() async {
    final response = await api.dio.get('/api/departments');
    return (response.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> setStaffActive(int id, bool active) async {
    await api.dio.patch('/api/staff/$id/status', data: {'active': active});
  }

  Future<Map<String, dynamic>> statistics(
      int id, String period, String date) async {
    final response = await api.dio.get('/api/statistics', queryParameters: {
      'staffId': id,
      'period': period,
      'date': date,
    });
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> history([int? id]) async {
    final r = await api.dio.get(
      '/api/attendance/history',
      queryParameters: ifId(id),
    );
    return (r.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<Attendance>> myAttendance() async {
    final rows = (await history()).map(Attendance.fromJson).toList();
    rows.sort((a, b) => b.checkInUtc.compareTo(a.checkInUtc));
    return rows;
  }

  Future<Attendance> checkIn({GpsCoordinates? location}) =>
      _checkAttendance('check-in', location);
  Future<AttendanceLocationPolicy> attendanceLocationPolicy() async =>
      AttendanceLocationPolicy.fromJson(Map<String, dynamic>.from(
          (await api.dio.get('/api/attendance/location-policy')).data as Map));
  Future<Attendance> checkOut({GpsCoordinates? location}) =>
      _checkAttendance('check-out', location);
  Future<Attendance> _checkAttendance(String action, GpsCoordinates? location,
      {String method = 'manual'}) async {
    // Ordinary self-service attendance uses JWT, without biometric verification.
    final response = await api.dio.post('/api/attendance/$action', data: {
      'method': method,
      if (location != null && location.isValid) ...{
        'latitude': location.latitude,
        'longitude': location.longitude,
        if (location.accuracy != null) 'accuracy': location.accuracy,
        if (location.capturedAtUtc != null)
          'capturedAtUtc': location.capturedAtUtc!.toUtc().toIso8601String(),
      },
    });
    return Attendance.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<Attendance> biometricCheckIn({GpsCoordinates? location}) =>
      _checkAttendance('check-in', location, method: 'biometric');
  Future<Attendance> biometricCheckOut({GpsCoordinates? location}) =>
      _checkAttendance('check-out', location, method: 'biometric');

  Map<String, dynamic>? ifId(int? id) => id == null ? null : {'staffId': id};
  Future<Map<String, dynamic>> report(
    int id,
    DateTime from,
    DateTime to,
  ) async {
    final r = await api.dio.get(
      '/api/reports',
      queryParameters: {
        'staffId': id,
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(r.data as Map);
  }

  Future<String> emailReport(int id, DateTime from, DateTime to) async {
    final response = await api.dio.post(
      '/api/reports/email',
      queryParameters: {
        'staffId': id,
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
    );
    final data = response.data;
    if (data is! Map ||
        data['sentTo'] is! String ||
        (data['sentTo'] as String).isEmpty) {
      throw const FormatException('Máy chủ chưa xác nhận kết quả gửi báo cáo.');
    }
    return data['sentTo'] as String;
  }

  Future<void> addStaff({
    required String name,
    required String email,
    required String password,
    required int role,
    required double hourlyRate,
    int? managerId,
    int? departmentId,
  }) async {
    await api.dio.post(
      '/api/staff',
      data: {
        'name': name,
        'email': email,
        'password': password,
        'role': role,
        'hourlyRate': hourlyRate,
        'managerId': managerId,
        'departmentId': departmentId,
      },
    );
  }

  Future<void> updateStaff(int id, Map<String, dynamic> data) async {
    await api.dio.put('/api/staff/$id', data: data);
  }

  Future<void> manualAttendance(
    int staffId,
    DateTime start,
    DateTime end,
    String reason,
  ) async {
    await api.dio.post(
      '/api/attendance/manual',
      data: {
        'staffId': staffId,
        'checkInUtc': start.toUtc().toIso8601String(),
        'checkOutUtc': end.toUtc().toIso8601String(),
        'reason': reason,
      },
    );
  }
}
