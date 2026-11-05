import 'package:dio/dio.dart';
import 'aquar_service.dart';

class ManagementService {
  ManagementService(this.session);
  final AquarService session;
  Dio get client => session.api.dio;
  Future<List<Map<String, dynamic>>> payroll(int year, int month) async =>
      _rows((await client.get('/api/monthly-payroll',
              queryParameters: {'year': year, 'month': month}))
          .data);
  Future<Map<String, dynamic>?> salaryConfiguration(int staffId) async {
    try {
      return Map<String, dynamic>.from(
          (await client.get('/api/monthly-payroll/configuration/$staffId')).data
              as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> saveSalary(int staffId, Map<String, dynamic> data) async {
    await client.put('/api/monthly-payroll/configuration/$staffId', data: data);
  }

  Future<void> calculate(int staffId, Map<String, dynamic> data) async {
    await client.post('/api/monthly-payroll/$staffId/calculate', data: data);
  }

  Future<void> transition(int id, String version, bool close) async {
    await client.post('/api/monthly-payroll/$id/${close ? 'close' : 'approve'}',
        data: {'version': version});
  }

  Future<String> exportPayroll(int year, int month) async =>
      (await client.get<String>('/api/monthly-payroll/export',
              queryParameters: {'year': year, 'month': month},
              options: Options(responseType: ResponseType.plain)))
          .data!;
  Future<void> saveDepartment(int? id, String name, String description) async {
    final data = {'name': name, 'description': description};
    if (id == null) {
      await client.post('/api/departments', data: data);
    } else {
      await client.put('/api/departments/$id', data: data);
    }
  }

  Future<void> resetPassword(int staffId, String password) async {
    await client.put('/api/accounts/$staffId/password',
        data: {'newPassword': password});
  }

  Future<List<Map<String, dynamic>>> alerts(
          {int? staffId,
          String? from,
          String? to,
          String? status,
          int skip = 0}) async =>
      _rows((await client
              .get('/api/location-administration/alerts', queryParameters: {
        if (staffId != null) 'staffId': staffId,
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        if (status != null) 'status': status,
        'skip': skip,
        'take': 100
      }))
          .data);
  Future<Map<String, dynamic>> company() async => Map<String, dynamic>.from(
      (await client.get('/api/location-administration/company')).data as Map);
  Future<void> saveCompany(Map<String, dynamic> data) async {
    await client.put('/api/location-administration/company', data: data);
  }

  static List<Map<String, dynamic>> _rows(dynamic data) =>
      (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}
