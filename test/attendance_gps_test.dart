import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:aquar_app/services/attendance_location.dart';
import 'package:aquar_app/services/aquar_service.dart';
import 'package:aquar_app/screens/attendance_page.dart';
import 'auth_test.dart' show MemoryTokens, fakeApi, jsonReply;
import 'attendance_test.dart' show AttendanceStub, employee, record;

class FakeDevice implements LocationDevice {
  bool services = true;
  LocationPermission granted = LocationPermission.whileInUse;
  LocationPermission requested = LocationPermission.denied;
  int requests = 0, positions = 0;
  Object? error;
  Completer<LocationPermission>? permissionGate;
  Completer<GpsCoordinates>? positionGate;
  @override
  Future<bool> enabled() async => services;
  @override
  Future<LocationPermission> permission() async => granted;
  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    if (permissionGate != null) return await permissionGate!.future;
    return requested;
  }

  @override
  Future<GpsCoordinates> position(Duration timeout) async {
    positions++;
    if (error != null) throw error!;
    if (positionGate != null) return await positionGate!.future;
    // Synthetic fixture only, never used by application code.
    return const GpsCoordinates(12.34, 56.78);
  }
}

void main() {
  test('GPS success reads current position exactly once', () async {
    final device = FakeDevice();
    final capture =
        await GeolocatorAttendanceLocation(device: device).captureOnce();
    expect(capture.coordinates?.latitude, 12.34);
    expect(device.positions, 1);
    expect(device.requests, 0);
  });
  test('Permission requested when needed; grant allows one fix', () async {
    final device = FakeDevice()
      ..granted = LocationPermission.denied
      ..requested = LocationPermission.whileInUse;
    expect(
        (await GeolocatorAttendanceLocation(device: device).captureOnce())
            .coordinates,
        isNotNull);
    expect(device.requests, 1);
    expect(device.positions, 1);
  });
  test('Denied permission falls back without reading position', () async {
    final device = FakeDevice()..granted = LocationPermission.denied;
    final capture =
        await GeolocatorAttendanceLocation(device: device).captureOnce();
    expect(capture.coordinates, isNull);
    expect(capture.message, contains('chưa xác minh'));
    expect(device.requests, 1);
    expect(device.positions, 0);
  });
  test('Denied forever does not repeatedly prompt', () async {
    final device = FakeDevice()..granted = LocationPermission.deniedForever;
    expect(
        (await GeolocatorAttendanceLocation(device: device).captureOnce())
            .coordinates,
        isNull);
    expect(device.requests, 0);
    expect(device.positions, 0);
  });
  test('GPS off falls back without requesting permission', () async {
    final device = FakeDevice()..services = false;
    final capture =
        await GeolocatorAttendanceLocation(device: device).captureOnce();
    expect(capture.coordinates, isNull);
    expect(capture.message, contains('đang tắt'));
    expect(device.requests, 0);
    expect(device.positions, 0);
  });
  test('Position timeout falls back', () async {
    final device = FakeDevice()..error = TimeoutException('test');
    expect(
        (await GeolocatorAttendanceLocation(device: device).captureOnce())
            .message,
        contains('Hết thời gian'));
  });
  test('Total timeout prevents late permission result starting GPS', () async {
    final gate = Completer<LocationPermission>();
    final device = FakeDevice()
      ..granted = LocationPermission.denied
      ..permissionGate = gate;
    final capture = await GeolocatorAttendanceLocation(
            device: device, totalTimeout: const Duration(milliseconds: 1))
        .captureOnce();
    expect(capture.coordinates, isNull);
    gate.complete(LocationPermission.whileInUse);
    await Future<void>.delayed(Duration.zero);
    expect(device.positions, 0);
  });
  test('Device exception falls back rather than blocking attendance', () async {
    final device = FakeDevice()..error = Exception('device unavailable');
    expect(
        (await GeolocatorAttendanceLocation(device: device).captureOnce())
            .coordinates,
        isNull);
  });
  for (final checkIn in [true, false]) {
    test(
        'API ${checkIn ? 'check-in' : 'check-out'} sends coordinates with manual',
        () async {
      final api = fakeApi(MemoryTokens(), (request) {
        expect(request.path,
            '/api/attendance/${checkIn ? 'check-in' : 'check-out'}');
        expect(request.data,
            {'method': 'manual', 'latitude': 12.34, 'longitude': 56.78});
        return jsonReply(record(closed: !checkIn));
      });
      final service = AquarService(api: api);
      if (checkIn) {
        await service.checkIn(location: const GpsCoordinates(12.34, 56.78));
      } else {
        await service.checkOut(location: const GpsCoordinates(12.34, 56.78));
      }
    });
    for (final reason in ['success', 'denied', 'off', 'timeout']) {
      testWidgets(
          '${checkIn ? 'Check-in' : 'Check-out'} still completes when GPS is $reason',
          (tester) async {
        final device = FakeDevice();
        if (reason == 'denied') device.granted = LocationPermission.denied;
        if (reason == 'off') device.services = false;
        if (reason == 'timeout') device.error = TimeoutException('test');
        final service = AttendanceStub();
        if (!checkIn) service.rows = [await service.checkIn()];
        service.checkIns = 0;
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: AttendancePage(
                    user: employee,
                    service: service,
                    locationProvider:
                        GeolocatorAttendanceLocation(device: device)))));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key(checkIn ? 'check-in' : 'check-out')));
        await tester.pumpAndSettle();
        expect(checkIn ? service.checkIns : service.checkOuts, 1);
        final sent = checkIn
            ? service.lastCheckInLocation
            : service.lastCheckOutLocation;
        expect(sent, reason == 'success' ? isNotNull : isNull);
        expect(
            find.descendant(
                of: find.byKey(const Key('attendance-result')),
                matching: find.text(checkIn
                    ? 'Check-in thành công.'
                    : 'Check-out thành công.')),
            findsOneWidget);
        if (reason != 'success') {
          expect(
              tester
                  .widget<Text>(find.byKey(const Key('location-notice')))
                  .data,
              contains('chưa xác minh'));
        }
      });
    }
  }
}
