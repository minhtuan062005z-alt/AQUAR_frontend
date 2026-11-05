import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquar_app/models/attendance.dart';
import 'package:aquar_app/services/attendance_location.dart';
import 'package:aquar_app/services/aquar_service.dart';
import 'package:aquar_app/screens/location_administration_page.dart';
import 'attendance_test.dart' show AttendanceStub, showPage, inButton, record;
import 'attendance_gps_test.dart' show FakeDevice;
import 'attendance_result_test.dart' show location;
import 'staff_report_test.dart' show admin, manager, employee;
import 'auth_test.dart' show fakeApi, MemoryTokens, jsonReply;

class NoPolicy extends AttendanceStub {
  @override
  Future<AttendanceLocationPolicy> attendanceLocationPolicy() async =>
      throw DioException(
          requestOptions:
              RequestOptions(path: '/api/attendance/location-policy'),
          type: DioExceptionType.connectionError);
}

class StaleDevice extends FakeDevice {
  @override
  Future<GpsCoordinates> position(Duration timeout) async => GpsCoordinates(
      10, 106,
      accuracy: 5,
      capturedAtUtc:
          DateTime.now().toUtc().subtract(const Duration(minutes: 5)));
}

void main() {
  test('Provider discards stale GPS rather than sending cached coordinates',
      () async {
    final result =
        await GeolocatorAttendanceLocation(device: StaleDevice()).captureOnce();
    expect(result.coordinates, isNull);
    expect(result.message, contains('quá cũ'));
  });
  testWidgets(
      'History renders separate authoritative event status, method and radius',
      (tester) async {
    final service = AttendanceStub()
      ..rows = [
        Attendance.fromJson({
          ...record(closed: true),
          'checkInLocation': {
            ...location('Unverified'),
            'verificationStatus': 'VERIFIED',
            'verificationReason': 'ClientCoordinatesCompared',
            'radiusMeters': 100,
            'accuracy': 5,
            'method': 'manual'
          },
          'checkOutLocation': {
            ...location('Unverified', distance: 240),
            'verificationStatus': 'OUT_OF_RANGE',
            'verificationReason': 'OutsideCompanyRadius',
            'radiusMeters': 100,
            'accuracy': 5,
            'method': 'biometric'
          }
        })
      ];
    await showPage(tester, service);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Trong phạm vi công ty'), findsOneWidget);
    expect(find.text('Ngoài phạm vi công ty'), findsOneWidget);
    expect(find.text('Bán kính cho phép: 100.0 m'), findsNWidgets(2));
    expect(find.text('Phương thức: Sinh trắc học hệ thống'), findsOneWidget);
  });
  test('All canonical backend outcomes have distinct Vietnamese explanations',
      () {
    final labels = <String>{};
    for (final status in [
      'VERIFIED',
      'OUT_OF_RANGE',
      'LOW_ACCURACY',
      'GPS_UNAVAILABLE',
      'NOT_CONFIGURED',
      'NOT_VERIFIED'
    ]) {
      final value = AttendanceLocationInfo.fromJson({
        ...location('Unverified'),
        'verificationStatus': status,
        'verificationReason': status == 'NOT_CONFIGURED'
            ? 'CompanyNotConfigured'
            : 'NoLocationRecord',
        'radiusMeters': 100
      })!;
      expect(value.result, status);
      labels.add('${value.statusLabel} ${value.reasonLabel}');
    }
    expect(labels.length, 6);
  });
  test('Explicit verified backend result overrides legacy Unverified field',
      () {
    final value = AttendanceLocationInfo.fromJson({
      ...location('Unverified'),
      'verificationStatus': 'VERIFIED',
      'verificationReason': 'ClientCoordinatesCompared',
      'radiusMeters': 100,
      'accuracy': 5
    })!;
    expect(value.statusLabel, 'Trong phạm vi công ty');
    expect(value.displayedDistance, isNotNull);
    expect(value.radiusMeters, 100);
  });
  test('Coordinates alone never verify a legacy record', () {
    final value = AttendanceLocationInfo.fromJson(location('Unverified'))!;
    expect(value.result, 'NOT_VERIFIED');
    expect(value.isVerified, isFalse);
    expect(value.displayedDistance, isNull);
  });
  test('Company not configured explains cause without fabricating distance',
      () {
    final value = AttendanceLocationInfo.fromJson({
      ...location('Unverified'),
      'verificationStatus': 'NOT_CONFIGURED',
      'verificationReason': 'CompanyNotConfigured'
    })!;
    expect(value.reasonLabel, 'Công ty chưa cấu hình vị trí chấm công.');
    expect(value.displayedDistance, isNull);
  });
  test('Required policy rejects missing, inaccurate or stale GPS locally', () {
    const policy = AttendanceLocationPolicy(configured: true, required: true);
    expect(policy.permitsSubmission(null), isFalse);
    expect(
        policy.permitsSubmission(GpsCoordinates(10, 106,
            accuracy: 100, capturedAtUtc: DateTime.now().toUtc())),
        isFalse);
    expect(
        policy.permitsSubmission(GpsCoordinates(10, 106,
            accuracy: 5,
            capturedAtUtc:
                DateTime.now().toUtc().subtract(const Duration(minutes: 5)))),
        isFalse);
    expect(
        policy.permitsSubmission(GpsCoordinates(10, 106,
            accuracy: 5, capturedAtUtc: DateTime.now().toUtc())),
        isTrue);
  });
  testWidgets('Required GPS denial never falls back to attendance POST',
      (tester) async {
    final service = AttendanceStub()
      ..policy =
          const AttendanceLocationPolicy(configured: true, required: true);
    await showPage(tester, service);
    inButton(tester).onPressed!();
    await tester.pumpAndSettle();
    expect(service.checkIns, 0);
    expect(find.textContaining('Công ty yêu cầu GPS hợp lệ'), findsOneWidget);
  });
  testWidgets('Policy network failure never sends attendance POST',
      (tester) async {
    final service = NoPolicy();
    await showPage(tester, service);
    inButton(tester).onPressed!();
    await tester.pumpAndSettle();
    expect(service.checkIns, 0);
    expect(
        find.textContaining('Không đọc được chính sách GPS'), findsOneWidget);
  });
  testWidgets('Optional policy still permits attendance without GPS',
      (tester) async {
    final service = AttendanceStub();
    await showPage(tester, service);
    inButton(tester).onPressed!();
    await tester.pumpAndSettle();
    expect(service.checkIns, 1);
  });
  test('GPS payload includes actual accuracy and capture time', () async {
    final now = DateTime.utc(2026, 11, 5, 1);
    final service = AquarService(
        api: fakeApi(MemoryTokens(), (r) {
      expect((r.data as Map)['accuracy'], 8);
      expect((r.data as Map)['capturedAtUtc'], now.toIso8601String());
      return jsonReply({
        'id': 1,
        'staffId': 1,
        'checkInUtc': now.toIso8601String(),
        'method': 'manual',
        'manual': false
      });
    }));
    await service.checkIn(
        location: GpsCoordinates(10, 106, accuracy: 8, capturedAtUtc: now));
  });
  testWidgets('Manager sees scoped alerts but never company edit form',
      (tester) async {
    final paths = <String>[];
    final service = AquarService(
        api: fakeApi(MemoryTokens(), (r) {
      paths.add(r.path);
      return jsonReply([]);
    }));
    await tester.pumpWidget(MaterialApp(
        home: LocationAdministrationPage(user: manager, service: service)));
    await tester.pumpAndSettle();
    expect(paths, contains('/api/location-administration/alerts'));
    expect(paths, isNot(contains('/api/location-administration/company')));
    expect(find.text('Lưu cấu hình GPS'), findsNothing);
  });
  testWidgets('Employee direct GPS administration makes no API requests',
      (tester) async {
    var calls = 0;
    final service = AquarService(
        api: fakeApi(MemoryTokens(), (_) {
      calls++;
      return jsonReply([]);
    }));
    await tester.pumpWidget(MaterialApp(
        home: LocationAdministrationPage(user: employee, service: service)));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Bạn không có quyền quản lý GPS.'), findsOneWidget);
  });
  testWidgets('Admin validates coordinates and sends explicit versioned policy',
      (tester) async {
    Map<String, dynamic> company = {
      'latitude': null,
      'longitude': null,
      'radiusMeters': 100,
      'maxAccuracyMeters': 50,
      'maxAgeSeconds': 30,
      'requireGpsVerification': false,
      'editable': true,
      'version': 'fixture-version',
      'updatedAtUtc': null
    };
    Map? sent;
    final service = AquarService(
        api: fakeApi(MemoryTokens(), (r) {
      if (r.path == '/api/location-administration/company') {
        if (r.method == 'PUT') {
          sent = r.data as Map;
          company = {...company, ...Map<String, dynamic>.from(sent!)};
        }
        return jsonReply(company);
      }
      return jsonReply([]);
    }));
    await tester.pumpWidget(MaterialApp(
        home: LocationAdministrationPage(user: admin, service: service)));
    await tester.pumpAndSettle();
    expect(
        find.text('Công ty chưa cấu hình vị trí chấm công.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('Vĩ độ')), '91');
    await tester.enterText(find.byKey(const Key('Kinh độ')), '106');
    tester.testTextInput.hide();
    await tester.ensureVisible(find.text('Lưu cấu hình GPS'));
    await tester.tap(find.text('Lưu cấu hình GPS'));
    await tester.pumpAndSettle();
    expect(sent, isNull);
    expect(find.text('Tọa độ không hợp lệ.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('Vĩ độ')));
    await tester.enterText(find.byKey(const Key('Vĩ độ')), '10');
    tester.testTextInput.hide();
    await tester.ensureVisible(find.text('Lưu cấu hình GPS'));
    await tester.tap(find.text('Lưu cấu hình GPS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(sent?['latitude'], 10);
    expect(sent?['longitude'], 106);
    expect(sent?['version'], 'fixture-version');
    expect(sent?['requireGpsVerification'], false);
  });
  testWidgets(
      'GPS administration errors are visible without fabricated configuration',
      (tester) async {
    final service = AquarService(
        api: fakeApi(MemoryTokens(),
            (_) => jsonReply({'message': 'Máy chủ GPS không sẵn sàng.'}, 503)));
    await tester.pumpWidget(MaterialApp(
        home: LocationAdministrationPage(user: admin, service: service)));
    await tester.pumpAndSettle();
    expect(find.text('Máy chủ GPS không sẵn sàng.'), findsWidgets);
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Lưu cấu hình GPS'));
    expect(button.onPressed, isNull);
  });
}
