import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquar_app/core/api.dart';
import 'package:aquar_app/models/attendance.dart';
import 'package:aquar_app/models/user.dart';
import 'package:aquar_app/screens/attendance_page.dart';
import 'package:aquar_app/services/aquar_service.dart';
import 'package:aquar_app/services/attendance_location.dart';
import 'auth_test.dart' show MemoryTokens, fakeApi, jsonReply;

Map<String, dynamic> record({bool closed = false}) => {
      'id': 10,
      'staffId': 1,
      'checkInUtc': '2026-11-05T01:00:00',
      'checkOutUtc': closed ? '2026-11-05T09:00:00Z' : null,
      'method': 'manual',
      'manual': false,
    };

class AttendanceStub extends AquarService {
  AttendanceStub() : super(api: fakeApi(MemoryTokens(), (_) => jsonReply({})));
  List<Attendance> rows = [];
  Object? historyError, actionError;
  Completer<List<Attendance>>? historyGate;
  Completer<Attendance>? actionGate;
  int checkIns = 0, checkOuts = 0, reads = 0;
  AttendanceLocationPolicy policy =
      const AttendanceLocationPolicy(configured: false, required: false);
  @override
  Future<AttendanceLocationPolicy> attendanceLocationPolicy() async => policy;
  GpsCoordinates? lastCheckInLocation, lastCheckOutLocation;
  @override
  Future<List<Attendance>> myAttendance() async {
    reads++;
    if (historyError != null) throw historyError!;
    if (historyGate != null) return await historyGate!.future;
    return List.of(rows);
  }

  @override
  Future<Attendance> checkIn({GpsCoordinates? location}) async {
    lastCheckInLocation = location;
    checkIns++;
    if (actionError != null) throw actionError!;
    final item = actionGate == null
        ? Attendance.fromJson(record())
        : await actionGate!.future;
    rows = [item];
    return item;
  }

  @override
  Future<Attendance> checkOut({GpsCoordinates? location}) async {
    lastCheckOutLocation = location;
    checkOuts++;
    if (actionError != null) throw actionError!;
    final item = Attendance.fromJson(record(closed: true));
    rows = [item];
    return item;
  }
}

class NoLocation implements AttendanceLocationProvider {
  @override
  Future<LocationCapture> captureOnce() async =>
      const LocationCapture.unavailable('Vị trí chưa xác minh.');
}

const employee = AquarUser(
    id: 1, name: 'Test', email: 'test@example.invalid', role: 'Employee');
Future<void> showPage(WidgetTester tester, AttendanceStub service) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: AttendancePage(
              user: employee,
              service: service,
              locationProvider: NoLocation()))));
  await tester.pumpAndSettle();
}

FilledButton inButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('check-in')));
OutlinedButton outButton(WidgetTester tester) =>
    tester.widget<OutlinedButton>(find.byKey(const Key('check-out')));
void main() {
  test('SQL datetime2 without suffix is interpreted as UTC', () {
    final value = Attendance.fromJson(record());
    expect(value.checkInUtc, DateTime.utc(2026, 11, 5, 1));
    expect(value.checkInUtc.isUtc, isTrue);
    expect(value.isOpen, isTrue);
    expect(value.method, 'manual');
    expect(value.manual, isFalse);
  });
  test('Legacy biometric history and manager corrections retain their meaning',
      () {
    final legacy = Attendance.fromJson({...record(), 'method': 'biometric'});
    expect(legacy.method, 'biometric');
    expect(legacy.manual, isFalse);
    final correction =
        Attendance.fromJson({...record(closed: true), 'manual': true});
    expect(correction.method, 'manual');
    expect(correction.manual, isTrue);
  });
  test('Completed shift parses checkout; malformed response is rejected', () {
    expect(Attendance.fromJson(record(closed: true)).isOpen, isFalse);
    expect(() => Attendance.fromJson({...record(), 'checkInUtc': 'invalid'}),
        throwsFormatException);
  });
  for (final action in ['check-in', 'check-out']) {
    test('$action uses exact endpoint, method, payload and JWT', () async {
      final tokens = MemoryTokens()..value = 'test-session';
      final api = fakeApi(tokens, (request) {
        expect(request.method, 'POST');
        expect(request.path, '/api/attendance/$action');
        expect(request.data, {'method': 'manual'});
        expect(request.headers['Authorization'], 'Bearer test-session');
        return jsonReply(record(closed: action == 'check-out'));
      });
      final service = AquarService(api: api);
      final value = action == 'check-in'
          ? await service.checkIn()
          : await service.checkOut();
      expect(value.id, 10);
      expect(value.method, 'manual');
      expect(value.manual, isFalse);
      expect(value.isOpen, action == 'check-in');
    });
  }
  test('Personal history uses GET without requesting another staff ID',
      () async {
    final api = fakeApi(MemoryTokens(), (request) {
      expect(request.method, 'GET');
      expect(request.path, '/api/attendance/history');
      expect(request.queryParameters, isEmpty);
      return jsonReply([record(closed: true)]);
    });
    expect((await AquarService(api: api).myAttendance()).single.id, 10);
  });
  for (final status in [401, 403]) {
    test('Attendance handles HTTP $status through existing auth interceptor',
        () async {
      final tokens = MemoryTokens()..value = 'test-session';
      final api = fakeApi(tokens, (_) => jsonReply({}, status));
      await expectLater(
          AquarService(api: api).checkIn(), throwsA(isA<DioException>()));
      expect(tokens.value, status == 401 ? isNull : isNotNull);
      expect(api.authEvent.value, status == 401 ? AuthEvent.expired : isNull);
    });
  }
  testWidgets('Empty history enables only check-in', (tester) async {
    await showPage(tester, AttendanceStub());
    expect(find.text('Chưa Check-in'), findsOneWidget);
    expect(find.text('Chưa có lịch sử chấm công.'), findsOneWidget);
    expect(inButton(tester).onPressed, isNotNull);
    expect(outButton(tester).onPressed, isNull);
  });
  testWidgets('Check-in/out update server state and history', (tester) async {
    final service = AttendanceStub();
    await showPage(tester, service);
    await tester.tap(find.byKey(const Key('check-in')));
    await tester.pumpAndSettle();
    expect(service.checkIns, 1);
    // AttendancePage is a Scaffold body in production. With that same harness,
    // pumpAndSettle completes the POST/GET microtasks and SnackBar entrance animation.
    expect(
        find.descendant(
            of: find.byType(SnackBar),
            matching: find.text('Check-in thành công.')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('attendance-result')),
            matching: find.text('Check-in thành công.')),
        findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('attendance-state'))).data,
        'Đang làm việc');
    expect(service.reads, 2);
    expect(
        find.descendant(
            of: find.byType(ListTile),
            matching: find.textContaining('Ra: Chưa có')),
        findsOneWidget);
    expect(inButton(tester).onPressed, isNull);
    expect(outButton(tester).onPressed, isNotNull);
    // Do not leave the first SnackBar at the front of ScaffoldMessenger's queue
    // when asserting the second notification. No four-second timer/sleep is needed.
    ScaffoldMessenger.of(tester.element(find.byType(AttendancePage)))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(SnackBar),
            matching: find.text('Check-in thành công.')),
        findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const Key('attendance-result')),
            matching: find.text('Check-in thành công.')),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('check-out')));
    await tester.pumpAndSettle();
    expect(service.checkOuts, 1);
    expect(
        find.descendant(
            of: find.byType(SnackBar),
            matching: find.text('Check-out thành công.')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('attendance-result')),
            matching: find.text('Check-out thành công.')),
        findsOneWidget);
    expect(find.text('Đã Check-out'), findsOneWidget);
    expect(service.reads, 3);
    expect(
        find.descendant(
            of: find.byType(ListTile),
            matching: find.textContaining('Đã Check-out')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(ListTile),
            matching: find.textContaining('Ra: Chưa có')),
        findsNothing);
    expect(inButton(tester).onPressed, isNotNull);
    expect(outButton(tester).onPressed, isNull);
    expect(service.rows.single.checkOutUtc, isNotNull);
  });
  testWidgets('Repeated taps send only one pending POST', (tester) async {
    final service = AttendanceStub()..actionGate = Completer<Attendance>();
    await showPage(tester, service);
    final callback = inButton(tester).onPressed!;
    callback();
    callback();
    await tester.pump();
    expect(service.checkIns, 1);
    expect(inButton(tester).onPressed, isNull);
    expect(outButton(tester).onPressed, isNull);
    service.actionGate!.complete(Attendance.fromJson(record()));
    await tester.pumpAndSettle();
  });
  testWidgets('Loading disables actions before history arrives',
      (tester) async {
    final service = AttendanceStub()
      ..historyGate = Completer<List<Attendance>>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AttendancePage(
                user: employee,
                service: service,
                locationProvider: NoLocation()))));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(inButton(tester).onPressed, isNull);
    service.historyGate!.complete([]);
    await tester.pumpAndSettle();
    expect(inButton(tester).onPressed, isNotNull);
  });
  testWidgets(
      'History failure offers retry and prevents writes with unknown state',
      (tester) async {
    final service = AttendanceStub()..historyError = Exception('network');
    await showPage(tester, service);
    expect(inButton(tester).onPressed, isNull);
    expect(outButton(tester).onPressed, isNull);
    expect(find.text('Thử lại'), findsOneWidget);
    service.historyError = null;
    await tester.ensureVisible(find.text('Thử lại'));
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(inButton(tester).onPressed, isNotNull);
  });
  testWidgets(
      'Conflict displays backend message and reloads without replaying POST',
      (tester) async {
    final request = RequestOptions(path: '/api/attendance/check-in');
    final service = AttendanceStub()
      ..actionError = DioException(
          requestOptions: request,
          response: Response(
              requestOptions: request,
              statusCode: 409,
              data: {'message': 'Ca làm chưa kết thúc.'}));
    await showPage(tester, service);
    await tester.tap(find.byKey(const Key('check-in')));
    await tester.pumpAndSettle();
    expect(find.text('Ca làm chưa kết thúc.'), findsOneWidget);
    expect(service.checkIns, 1);
    expect(service.reads, 2);
  });
  testWidgets('Timeout reconciles server result instead of submitting again',
      (tester) async {
    final service = AttendanceStub()
      ..actionError = DioException(
          requestOptions: RequestOptions(path: '/api/attendance/check-in'),
          type: DioExceptionType.receiveTimeout);
    await showPage(tester, service);
    // Server may have committed even though the response was lost.
    service.rows = [Attendance.fromJson(record())];
    await tester.tap(find.byKey(const Key('check-in')));
    await tester.pumpAndSettle();
    expect(service.checkIns, 1);
    expect(inButton(tester).onPressed, isNull);
    expect(outButton(tester).onPressed, isNotNull);
  });
}
