import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:aquar_app/services/aquar_service.dart';
import 'package:aquar_app/services/management_service.dart';
import 'package:aquar_app/services/attendance_biometrics.dart';
import 'package:aquar_app/services/attendance_location.dart';
import 'package:aquar_app/screens/attendance_page.dart';
import 'package:aquar_app/screens/payroll_page.dart';
import 'package:aquar_app/models/attendance.dart';
import 'auth_test.dart' show fakeApi, MemoryTokens, jsonReply;
import 'attendance_test.dart' show AttendanceStub, NoLocation, employee, record;

class FakeLocalAuth extends LocalAuthentication {
  bool hardware = true, supported = true, result = true;
  int prompts = 0, cancels = 0;
  List<BiometricType> enrolled = [BiometricType.strong];
  Completer<bool>? gate;
  @override
  Future<bool> get canCheckBiometrics async => hardware;
  @override
  Future<bool> isDeviceSupported() async => supported;
  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => enrolled;
  @override
  Future<bool> authenticate(
      {required String localizedReason,
      Iterable<Object> authMessages = const [],
      AuthenticationOptions options = const AuthenticationOptions()}) async {
    expect(options.biometricOnly, isTrue);
    expect(options.stickyAuth, isFalse);
    prompts++;
    return gate == null ? result : await gate!.future;
  }

  @override
  Future<bool> stopAuthentication() async {
    cancels++;
    return true;
  }
}

class BiometricStub extends AttendanceStub {
  int biometricIns = 0, biometricOuts = 0;
  @override
  Future<Attendance> biometricCheckIn({GpsCoordinates? location}) async {
    biometricIns++;
    return super.checkIn(location: location);
  }

  @override
  Future<Attendance> biometricCheckOut({GpsCoordinates? location}) async {
    biometricOuts++;
    return super.checkOut(location: location);
  }
}

Future<void> attendance(
    WidgetTester tester, BiometricStub service, FakeLocalAuth auth) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: AttendancePage(
              user: employee,
              service: service,
              locationProvider: NoLocation(),
              biometrics: SystemAttendanceBiometrics(auth: auth)))));
  await tester.pumpAndSettle();
}

void main() {
  test('Biometrics reject missing hardware and missing enrollment', () async {
    final auth = FakeLocalAuth()..hardware = false;
    final service = SystemAttendanceBiometrics(auth: auth);
    expect((await service.capability()).available, isFalse);
    expect(await service.authenticate(), isFalse);
    auth.hardware = true;
    auth.enrolled = [];
    expect((await service.capability()).message, contains('Chưa đăng ký'));
    expect(await service.authenticate(), isFalse);
    expect(auth.prompts, 0);
  });
  test('Android categories never claim confirmed face support', () async {
    final auth = FakeLocalAuth();
    expect((await SystemAttendanceBiometrics(auth: auth).capability()).message,
        contains('chưa xác nhận'));
    auth.enrolled = [BiometricType.fingerprint];
    expect((await SystemAttendanceBiometrics(auth: auth).capability()).message,
        contains('Có vân tay'));
  });
  testWidgets('Biometric timeout cancels prompt and returns failure',
      (tester) async {
    final auth = FakeLocalAuth()..gate = Completer<bool>();
    bool? result;
    SystemAttendanceBiometrics(auth: auth)
        .authenticate()
        .then((v) => result = v);
    await tester.pump();
    await tester.pump(const Duration(seconds: 46));
    await tester.pump();
    expect(result, isFalse);
    expect(auth.cancels, 1);
  });
  testWidgets('Cancelled authentication sends no attendance POST',
      (tester) async {
    final service = BiometricStub();
    final auth = FakeLocalAuth()..result = false;
    await attendance(tester, service, auth);
    await tester.ensureVisible(find.byKey(const Key('biometric-check-in')));
    await tester.tap(find.byKey(const Key('biometric-check-in')));
    await tester.pumpAndSettle();
    expect(service.biometricIns, 0);
    expect(service.checkIns, 0);
    expect(find.textContaining('Chưa gửi yêu cầu chấm công'), findsOneWidget);
  });
  testWidgets('Successful prompt sends once, fallback GPS remains optional',
      (tester) async {
    final service = BiometricStub();
    final auth = FakeLocalAuth()..gate = Completer<bool>();
    await attendance(tester, service, auth);
    final button = tester
        .widget<OutlinedButton>(find.byKey(const Key('biometric-check-in')));
    button.onPressed!();
    button.onPressed!();
    await tester.pump();
    expect(service.biometricIns, 0);
    auth.gate!.complete(true);
    await tester.pumpAndSettle();
    expect(auth.prompts, 1);
    expect(service.biometricIns, 1);
    expect(service.lastCheckInLocation, isNull);
    expect(find.byKey(const Key('attendance-result')), findsOneWidget);
  });
  testWidgets('Successful biometric checkout and history refresh',
      (tester) async {
    final service = BiometricStub()..rows = [Attendance.fromJson(record())];
    await attendance(tester, service, FakeLocalAuth());
    await tester.ensureVisible(find.byKey(const Key('biometric-check-out')));
    await tester.tap(find.byKey(const Key('biometric-check-out')));
    await tester.pumpAndSettle();
    expect(service.biometricOuts, 1);
    expect(service.rows.single.isOpen, isFalse);
    expect(service.reads, 2);
  });
  test('Biometric payload carries method and GPS for both endpoints', () async {
    var calls = 0;
    final service = AquarService(
        api: fakeApi(MemoryTokens(), (r) {
      expect(r.data,
          {'method': 'biometric', 'latitude': 10.5, 'longitude': 106.5});
      expect(
          r.path,
          calls++ == 0
              ? '/api/attendance/check-in'
              : '/api/attendance/check-out');
      return jsonReply({...record(closed: calls == 2), 'method': 'biometric'});
    }));
    await service.biometricCheckIn(location: const GpsCoordinates(10.5, 106.5));
    await service.biometricCheckOut(
        location: const GpsCoordinates(10.5, 106.5));
    expect(calls, 2);
  });
  test('Salary money is transmitted as decimal text without double conversion',
      () async {
    final service = AquarService(
        api: fakeApi(MemoryTokens(), (r) {
      expect(r.path, '/api/monthly-payroll/configuration/1');
      expect((r.data as Map)['monthlySalary'], '123456789.1234');
      return jsonReply({});
    }));
    await ManagementService(service)
        .saveSalary(1, {'monthlySalary': '123456789.1234'});
  });
  testWidgets('Employee sees own payroll without staff management controls',
      (tester) async {
    final service = AquarService(
        api: fakeApi(MemoryTokens(), (r) {
      expect(r.path, '/api/monthly-payroll');
      return jsonReply([
        {
          'id': 1,
          'staffId': 1,
          'state': 'Draft',
          'netPay': '123456789.1234',
          'validDays': '1',
          'note': 'Fixture'
        }
      ]);
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PayrollPage(user: employee, service: service))));
    await tester.pumpAndSettle();
    expect(find.text('Thực nhận: 123456789.1234 VND'), findsOneWidget);
    expect(find.text('Cấu hình lương'), findsNothing);
    expect(find.text('Xuất CSV'), findsNothing);
  });
  testWidgets('Payroll API error is visible, no fabricated salary',
      (tester) async {
    final service = AquarService(
        api: fakeApi(MemoryTokens(),
            (_) => jsonReply({'message': 'Chưa bật bảng lương.'}, 503)));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PayrollPage(user: employee, service: service))));
    await tester.pumpAndSettle();
    expect(find.text('Chưa bật bảng lương.'), findsOneWidget);
    expect(find.textContaining('Thực nhận:'), findsNothing);
  });
  testWidgets('Payroll network failure offers retry without write',
      (tester) async {
    final service = AquarService(
        api: fakeApi(
            MemoryTokens(),
            (r) => throw DioException(
                requestOptions: r, type: DioExceptionType.connectionError)));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PayrollPage(user: employee, service: service))));
    await tester.pumpAndSettle();
    expect(find.text('Tải lại bảng lương'), findsOneWidget);
    expect(find.textContaining('Thực nhận:'), findsNothing);
  });
}
