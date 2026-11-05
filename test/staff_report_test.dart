import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquar_app/core/api.dart';
import 'package:aquar_app/models/user.dart';
import 'package:aquar_app/models/staff_member.dart';
import 'package:aquar_app/services/aquar_service.dart';
import 'package:aquar_app/screens/staff_page.dart';
import 'package:aquar_app/screens/report_page.dart';
import 'auth_test.dart' show fakeApi, MemoryTokens, jsonReply;

const admin = AquarUser(
    id: 1,
    name: 'Admin Fixture',
    email: 'admin@example.invalid',
    role: 'Admin');
const manager = AquarUser(
    id: 2,
    name: 'Manager Fixture',
    email: 'manager@example.invalid',
    role: 'Manager');
const employee = AquarUser(
    id: 3,
    name: 'Employee Fixture',
    email: 'employee@example.invalid',
    role: 'Employee');
const person = StaffMember(
    id: 3,
    name: 'Employee Fixture',
    email: 'employee@example.invalid',
    role: 'Employee',
    active: true,
    hourlyRate: 30000,
    managerId: 2,
    departmentId: 7);

class ManagementStub extends AquarService {
  ManagementStub() : super(api: fakeApi(MemoryTokens(), (_) => jsonReply({})));
  List<StaffMember> people = [
    person,
    const StaffMember(
        id: 2,
        name: 'Manager Fixture',
        email: 'manager@example.invalid',
        role: 'Manager',
        active: true,
        hourlyRate: 40000)
  ];
  int staffReads = 0,
      creates = 0,
      updates = 0,
      statusChanges = 0,
      mailCalls = 0,
      manualCalls = 0;
  Map<String, dynamic>? saved, statisticsQuery;
  DateTime? emailedFrom, emailedTo;
  Object? staffError, mailError;
  Completer<String>? mailGate;
  @override
  Future<List<StaffMember>> staffMembers() async {
    staffReads++;
    if (staffError != null) throw staffError!;
    return people;
  }

  @override
  Future<List<Map<String, dynamic>>> departments() async => [
        {'id': 7, 'name': 'Fixture Department'}
      ];
  @override
  Future<void> addStaff(
      {required String name,
      required String email,
      required String password,
      required int role,
      required double hourlyRate,
      int? managerId,
      int? departmentId}) async {
    creates++;
    saved = {
      'name': name,
      'email': email,
      'passwordLength': password.length,
      'role': role,
      'hourlyRate': hourlyRate,
      'managerId': managerId,
      'departmentId': departmentId
    };
  }

  @override
  Future<void> updateStaff(int id, Map<String, dynamic> data) async {
    updates++;
    saved = {...data, 'id': id};
  }

  @override
  Future<void> setStaffActive(int id, bool active) async {
    statusChanges++;
    saved = {'id': id, 'active': active};
  }

  @override
  Future<void> manualAttendance(
      int staffId, DateTime start, DateTime end, String reason) async {
    manualCalls++;
  }

  @override
  Future<Map<String, dynamic>> statistics(
      int id, String period, String date) async {
    statisticsQuery = {'id': id, 'period': period, 'date': date};
    return {
      'staffId': id,
      'from': '2026-10-31T17:00:00Z',
      'to': '2026-11-30T17:00:00Z',
      'hours': 8,
      'grossSalary': 240000,
      'shifts': 1,
      'note': 'Fixture report'
    };
  }

  @override
  Future<String> emailReport(int id, DateTime from, DateTime to) async {
    mailCalls++;
    emailedFrom = from;
    emailedTo = to;
    if (mailError != null) throw mailError!;
    if (mailGate != null) return await mailGate!.future;
    return 'recipient@example.invalid';
  }
}

Future<void> staffPage(
    WidgetTester tester, AquarUser user, ManagementStub service) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: StaffPage(user: user, service: service))));
  await tester.pumpAndSettle();
}

Future<void> reportPage(
    WidgetTester tester, AquarUser user, ManagementStub service) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ReportPage(user: user, service: service))));
  await tester.pumpAndSettle();
}

DioException httpError(int status, String message) {
  final request = RequestOptions(path: '/api/reports/email');
  return DioException(
      requestOptions: request,
      response: Response(
          requestOptions: request,
          statusCode: status,
          data: {'message': message}));
}

void main() {
  test('Staff model accepts numeric/string roles and preserves assignment', () {
    for (final role in [2, 'Employee']) {
      final value = StaffMember.fromJson({
        'id': 3,
        'name': 'Test',
        'email': 'test@example.invalid',
        'role': role,
        'active': true,
        'hourlyRate': 30000,
        'managerId': 2,
        'departmentId': 7
      });
      expect(value.roleCode, 2);
      expect(value.departmentId, 7);
      expect(value.managerId, 2);
    }
  });
  test('Activation uses a PATCH containing only active', () async {
    final api = fakeApi(MemoryTokens(), (request) {
      expect(request.method, 'PATCH');
      expect(request.path, '/api/staff/3/status');
      expect(request.data, {'active': false});
      return jsonReply({});
    });
    await AquarService(api: api).setStaffActive(3, false);
  });
  test('Create staff includes Manager and department in Backend DTO', () async {
    final api = fakeApi(MemoryTokens(), (request) {
      expect(request.method, 'POST');
      expect(request.path, '/api/staff');
      expect((request.data as Map)['managerId'], 2);
      expect((request.data as Map)['departmentId'], 7);
      expect((request.data as Map)['role'], 2);
      return jsonReply({});
    });
    await AquarService(api: api).addStaff(
        name: 'Test',
        email: 'test@example.invalid',
        password: 'fixture-temporary-password',
        role: 2,
        hourlyRate: 30000,
        managerId: 2,
        departmentId: 7);
  });
  test('Statistics and email use exact endpoints and UTC query boundaries',
      () async {
    final from = DateTime.utc(2026, 10, 31, 17),
        to = DateTime.utc(2026, 11, 30, 17);
    final api = fakeApi(MemoryTokens(), (request) {
      if (request.path == '/api/statistics') {
        expect(request.method, 'GET');
        expect(request.queryParameters,
            {'staffId': 3, 'period': 'month', 'date': '2026-11-05'});
        return jsonReply({});
      }
      expect(request.method, 'POST');
      expect(request.path, '/api/reports/email');
      expect(request.queryParameters, {
        'staffId': 3,
        'from': from.toIso8601String(),
        'to': to.toIso8601String()
      });
      return jsonReply({'sentTo': 'recipient@example.invalid'});
    });
    final service = AquarService(api: api);
    await service.statistics(3, 'month', '2026-11-05');
    expect(await service.emailReport(3, from, to), 'recipient@example.invalid');
  });
  test('Conflict and validation errors retain Backend messages', () {
    expect(errorText(httpError(409, 'Email đã tồn tại.')), 'Email đã tồn tại.');
    final request = RequestOptions(path: '/api/staff');
    expect(
        errorText(DioException(
            requestOptions: request,
            response: Response(requestOptions: request, statusCode: 400, data: {
              'errors': {
                'Password': ['Mật khẩu cần ít nhất 12 ký tự.']
              }
            }))),
        'Mật khẩu cần ít nhất 12 ký tự.');
  });
  testWidgets('Employee direct staff screen makes no forbidden API call',
      (tester) async {
    final service = ManagementStub();
    await staffPage(tester, employee, service);
    expect(service.staffReads, 0);
    expect(find.text('Bạn không có quyền quản lý nhân viên.'), findsOneWidget);
  });
  testWidgets('Manager empty list explains assignment and has no create button',
      (tester) async {
    final service = ManagementStub()..people = [];
    await staffPage(tester, manager, service);
    expect(find.textContaining('Admin cần thiết lập'), findsOneWidget);
    expect(find.text('Thêm nhân viên / quản lý'), findsNothing);
  });
  testWidgets('Staff error renders retry and recovers', (tester) async {
    final service = ManagementStub()
      ..staffError = httpError(503, 'Máy chủ tạm lỗi');
    await staffPage(tester, admin, service);
    expect(find.text('Máy chủ tạm lỗi'), findsOneWidget);
    service.staffError = null;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Employee Fixture'), findsOneWidget);
    expect(service.staffReads, 2);
  });
  testWidgets(
      'Admin form blocks ten-character password then saves without disposed-controller errors',
      (tester) async {
    final service = ManagementStub();
    await staffPage(tester, admin, service);
    await tester.tap(find.text('Thêm nhân viên / quản lý'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('staff-name')), 'New Fixture');
    await tester.enterText(
        find.byKey(const Key('staff-email')), 'new@example.invalid');
    await tester.enterText(
        find.byKey(const Key('staff-password')), '1234567890');
    await tester.ensureVisible(find.byKey(const Key('staff-rate')));
    await tester.enterText(find.byKey(const Key('staff-rate')), '30000');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(service.creates, 0);
    expect(find.textContaining('Mật khẩu cần ít nhất 12'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('staff-password')));
    await tester.enterText(
        find.byKey(const Key('staff-password')), 'fixture-temporary-password');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(service.creates, 1);
    expect(service.saved!['role'], 2);
    expect(tester.takeException(), isNull);
    expect(
        find.text('Đã tạo tài khoản với mật khẩu tạm thời.'), findsOneWidget);
  });
  testWidgets(
      'Admin editing preserves current department, manager and active flag',
      (tester) async {
    final service = ManagementStub();
    await staffPage(tester, admin, service);
    final menu = find.descendant(
        of: find.byKey(const ValueKey('staff-3')),
        matching: find.byType(PopupMenuButton<String>));
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sửa thông tin / phân công'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(service.updates, 1);
    expect(service.saved!['departmentId'], 7);
    expect(service.saved!['managerId'], 2);
    expect(service.saved!['active'], isTrue);
    expect(service.saved!.containsKey('password'), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Employee report uses own server statistics without loading staff',
      (tester) async {
    final service = ManagementStub();
    await reportPage(tester, employee, service);
    await tester.tap(find.text('Xem báo cáo'));
    await tester.pumpAndSettle();
    expect(service.staffReads, 0);
    expect(service.statisticsQuery!['id'], employee.id);
    expect(service.statisticsQuery!['period'], 'month');
    expect(find.text('Tổng giờ: 8'), findsOneWidget);
    expect(find.byKey(const Key('report-person')), findsNothing);
  });
  testWidgets(
      'Email uses Backend period, confirms recipient and prevents repeated sends',
      (tester) async {
    final service = ManagementStub()..mailGate = Completer<String>();
    await reportPage(tester, employee, service);
    final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Gửi email'));
    button.onPressed!();
    button.onPressed!();
    await tester.pump();
    expect(service.mailCalls, 1);
    expect(service.emailedFrom, DateTime.utc(2026, 10, 31, 17));
    expect(service.emailedTo, DateTime.utc(2026, 11, 30, 17));
    expect(find.byKey(const Key('email-confirmation')), findsNothing);
    service.mailGate!.complete('recipient@example.invalid');
    await tester.pumpAndSettle();
    expect(find.text('SMTP đã nhận báo cáo gửi đến recipient@example.invalid.'),
        findsOneWidget);
  });
  testWidgets('SMTP 503 is displayed and never reports success',
      (tester) async {
    final service = ManagementStub()
      ..mailError = httpError(503, 'SMTP chưa cấu hình Host và From.');
    await reportPage(tester, employee, service);
    await tester.tap(find.text('Gửi email'));
    await tester.pumpAndSettle();
    expect(find.text('SMTP chưa cấu hình Host và From.'), findsOneWidget);
    expect(find.byKey(const Key('email-confirmation')), findsNothing);
    expect(service.mailCalls, 1);
  });
}
