import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:aquar_app/models/attendance.dart';
import 'package:aquar_app/services/attendance_location.dart';
import 'package:aquar_app/services/aquar_service.dart';
import 'auth_test.dart' show fakeApi, MemoryTokens, jsonReply;
import 'attendance_test.dart' show AttendanceStub, showPage, record;

Map<String, dynamic> location(String status,
        {bool coordinates = true, double? distance = 42.5, String? reason}) =>
    {
      'latitude': coordinates ? 12.34 : null,
      'longitude': coordinates ? 56.78 : null,
      'distanceMeters': distance,
      'status': status,
      'verificationReason': reason,
    };

class ResultStub extends AttendanceStub {
  Attendance response = Attendance.fromJson(record());
  @override
  Future<Attendance> checkIn({GpsCoordinates? location}) async {
    checkIns++;
    if (actionError != null) throw actionError!;
    rows = [response];
    return response;
  }

  @override
  Future<Attendance> checkOut({GpsCoordinates? location}) async {
    checkOuts++;
    if (actionError != null) throw actionError!;
    rows = [response];
    return response;
  }
}

Finder get panel => find.byKey(const Key('attendance-result'));
Finder panelText(String value) =>
    find.descendant(of: panel, matching: find.text(value));
Future<void> click(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Success stays visible while history refresh is still pending',
      (tester) async {
    final service = ResultStub();
    await showPage(tester, service);
    service.historyGate = Completer<List<Attendance>>();
    await tester.tap(find.byKey(const Key('check-in')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(panelText('Check-in thành công.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    service.historyGate!.complete([service.response]);
    await tester.pumpAndSettle();
    expect(panelText('Check-in thành công.'), findsOneWidget);
    expect(service.checkIns, 1);
  });
  test('Service retains Backend GPS and separate check-in/out locations',
      () async {
    final data = {
      ...record(closed: true),
      'checkInLocation': location('InRange'),
      'checkOutLocation': location('OutOfRange', distance: 180)
    };
    final api = fakeApi(MemoryTokens(), (_) => jsonReply(data));
    final value = await AquarService(api: api).checkOut();
    expect(value.checkInLocation?.statusLabel, 'Trong phạm vi công ty');
    expect(value.checkOutLocation?.statusLabel, 'Ngoài phạm vi công ty');
    expect(value.checkOutLocation?.distanceMeters, 180);
  });
  test(
      'Missing coordinates, company or unknown status never fabricate verification/distance',
      () {
    for (final data in [
      location('InRange', coordinates: false),
      location('Unverified', reason: 'CompanyNotConfigured'),
      location('unknown')
    ]) {
      final value = AttendanceLocationInfo.fromJson(data)!;
      expect(value.statusLabel, 'Chưa xác minh vị trí');
      expect(value.displayedDistance, isNull);
    }
    expect(
        AttendanceLocationInfo.fromJson(location('InRange', distance: 0))
            ?.displayedDistance,
        0);
  });
  testWidgets(
      'Pinned result uses Backend time/GPS and survives history reload and expired SnackBar',
      (tester) async {
    final service = ResultStub()
      ..response = Attendance.fromJson(
          {...record(), 'checkInLocation': location('InRange')});
    await showPage(tester, service);
    await click(tester, 'check-in');
    expect(panelText('Check-in thành công.'), findsOneWidget);
    expect(panelText('GPS: 12.340000, 56.780000'), findsOneWidget);
    expect(panelText('Khoảng cách đến công ty: 42.5 m'), findsOneWidget);
    expect(panelText('Trong phạm vi công ty'), findsOneWidget);
    final expectedTime = DateFormat('dd/MM/yyyy HH:mm:ss')
        .format(service.response.checkInUtc.toLocal());
    expect(panelText('Thời gian Backend: $expectedTime'), findsOneWidget);
    expect(service.reads, 2);
    ScaffoldMessenger.of(tester.element(panel)).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(panelText('Check-in thành công.'), findsOneWidget);
    expect(service.reads, 3);
    expect(service.checkIns, 1);
    // Scrolling history does not move the pinned result out of view.
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(panelText('Check-in thành công.').hitTestable(), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(ListTile),
            matching: find.text('GPS: 12.340000, 56.780000')),
        findsOneWidget);
  });
  testWidgets(
      'No GPS still shows success and unverified, without invented distance',
      (tester) async {
    final service = ResultStub();
    await showPage(tester, service);
    await click(tester, 'check-in');
    expect(panelText('Check-in thành công.'), findsOneWidget);
    expect(panelText('Chưa xác minh vị trí'), findsOneWidget);
    expect(
        find.descendant(
            of: panel, matching: find.textContaining('Khoảng cách')),
        findsNothing);
  });
  testWidgets('Company not configured keeps reported GPS but shows unverified',
      (tester) async {
    final service = ResultStub()
      ..response = Attendance.fromJson({
        ...record(),
        'checkInLocation': location('Unverified',
            distance: null, reason: 'CompanyNotConfigured')
      });
    await showPage(tester, service);
    await click(tester, 'check-in');
    expect(panelText('GPS: 12.340000, 56.780000'), findsOneWidget);
    expect(panelText('Chưa xác minh vị trí'), findsOneWidget);
    expect(
        find.descendant(
            of: panel, matching: find.textContaining('Khoảng cách')),
        findsNothing);
  });
  testWidgets(
      'Checkout result uses checkout time/location and history displays both events',
      (tester) async {
    final service = ResultStub()
      ..rows = [Attendance.fromJson(record())]
      ..response = Attendance.fromJson({
        ...record(closed: true),
        'checkInLocation': location('InRange'),
        'checkOutLocation': location('OutOfRange', distance: 180)
      });
    await showPage(tester, service);
    await click(tester, 'check-out');
    expect(panelText('Check-out thành công.'), findsOneWidget);
    expect(panelText('Ngoài phạm vi công ty'), findsOneWidget);
    expect(panelText('Khoảng cách đến công ty: 180.0 m'), findsOneWidget);
    final expectedTime = DateFormat('dd/MM/yyyy HH:mm:ss')
        .format(service.response.checkOutUtc!.toLocal());
    expect(panelText('Thời gian Backend: $expectedTime'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(ListTile), matching: find.text('Vị trí Check-out')),
        findsOneWidget);
    expect(service.checkOuts, 1);
    expect(service.reads, 2);
  });
  testWidgets(
      'History GET failure after successful POST does not remove result',
      (tester) async {
    final service = ResultStub();
    await showPage(tester, service);
    service.historyError = Exception('network');
    await click(tester, 'check-in');
    expect(panelText('Check-in thành công.'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
    expect(service.checkIns, 1);
    expect(service.reads, 2);
  });
  testWidgets('API error does not report success or retry POST',
      (tester) async {
    final request = RequestOptions(path: '/api/attendance/check-in');
    final service = ResultStub()
      ..actionError = DioException(
          requestOptions: request,
          response: Response(
              requestOptions: request,
              statusCode: 400,
              data: {'message': 'Không ghi được ca.'}));
    await showPage(tester, service);
    await click(tester, 'check-in');
    expect(panel, findsNothing);
    expect(find.text('Không ghi được ca.'), findsOneWidget);
    expect(service.checkIns, 1);
    expect(service.reads, 2);
  });
  testWidgets(
      'Timeout on later POST retains last success without claiming new success',
      (tester) async {
    final service = ResultStub();
    await showPage(tester, service);
    await click(tester, 'check-in');
    service.actionError = DioException(
        requestOptions: RequestOptions(path: '/api/attendance/check-out'),
        type: DioExceptionType.receiveTimeout);
    await click(tester, 'check-out');
    expect(panelText('Check-in thành công.'), findsOneWidget);
    expect(panelText('Check-out thành công.'), findsNothing);
    expect(panelText('Lần chấm công thành công gần nhất'), findsOneWidget);
    expect(service.checkOuts, 1);
  });
}
