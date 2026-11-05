import 'dart:async';
import 'package:geolocator/geolocator.dart';

class GpsCoordinates {
  const GpsCoordinates(this.latitude, this.longitude,
      {this.accuracy, this.capturedAtUtc});
  final double latitude, longitude;
  final double? accuracy;
  final DateTime? capturedAtUtc;
  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

class LocationCapture {
  const LocationCapture.available(this.coordinates) : message = null;
  const LocationCapture.unavailable(this.message) : coordinates = null;
  final GpsCoordinates? coordinates;
  final String? message;
}

abstract class AttendanceLocationProvider {
  Future<LocationCapture> captureOnce();
}

// An injectable boundary keeps permission/device APIs out of widget tests.
abstract class LocationDevice {
  Future<bool> enabled();
  Future<LocationPermission> permission();
  Future<LocationPermission> requestPermission();
  Future<GpsCoordinates> position(Duration timeout);
}

class GeolocatorDevice implements LocationDevice {
  @override
  Future<bool> enabled() => Geolocator.isLocationServiceEnabled();
  @override
  Future<LocationPermission> permission() => Geolocator.checkPermission();
  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();
  @override
  Future<GpsCoordinates> position(Duration timeout) async {
    final value = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high, timeLimit: timeout));
    final now = DateTime.now().toUtc();
    if (now.difference(value.timestamp.toUtc()) > const Duration(seconds: 30) ||
        value.timestamp.toUtc().isAfter(now.add(const Duration(seconds: 5)))) {
      throw const FormatException('GPS trả vị trí quá cũ hoặc sai thời gian.');
    }
    if (!value.accuracy.isFinite || value.accuracy < 0) {
      throw const FormatException('Độ chính xác GPS không hợp lệ.');
    }
    return GpsCoordinates(value.latitude, value.longitude,
        accuracy: value.accuracy, capturedAtUtc: value.timestamp.toUtc());
  }
}

class GeolocatorAttendanceLocation implements AttendanceLocationProvider {
  GeolocatorAttendanceLocation(
      {LocationDevice? device,
      this.positionTimeout = const Duration(seconds: 10),
      this.totalTimeout = const Duration(seconds: 20)})
      : device = device ?? GeolocatorDevice();
  final LocationDevice device;
  final Duration positionTimeout, totalTimeout;
  static const timeoutMessage = 'Hết thời gian lấy GPS; vị trí chưa xác minh.';
  @override
  Future<LocationCapture> captureOnce() async {
    var expired = false;
    try {
      return await _attempt(() => expired).timeout(totalTimeout, onTimeout: () {
        expired = true;
        return const LocationCapture.unavailable(timeoutMessage);
      });
    } on TimeoutException {
      return const LocationCapture.unavailable(timeoutMessage);
    } catch (_) {
      return const LocationCapture.unavailable(
          'Không lấy được GPS; vị trí chưa xác minh.');
    } finally {
      expired = true;
    }
  }

  Future<LocationCapture> _attempt(bool Function() expired) async {
    if (!await device.enabled()) {
      return const LocationCapture.unavailable(
          'Dịch vụ định vị đang tắt; vị trí chưa xác minh.');
    }
    if (expired()) return const LocationCapture.unavailable(timeoutMessage);
    var permission = await device.permission();
    if (expired()) return const LocationCapture.unavailable(timeoutMessage);
    if (permission == LocationPermission.denied) {
      permission = await device.requestPermission();
    }
    if (expired()) return const LocationCapture.unavailable(timeoutMessage);
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return const LocationCapture.unavailable(
          'Chưa được cấp quyền vị trí; vị trí chưa xác minh.');
    }
    final coordinates = await device.position(positionTimeout);
    if (expired()) return const LocationCapture.unavailable(timeoutMessage);
    if (!coordinates.isValid) {
      return const LocationCapture.unavailable(
          'GPS không hợp lệ; vị trí chưa xác minh.');
    }
    final captured = coordinates.capturedAtUtc;
    if (captured != null) {
      final age = DateTime.now().toUtc().difference(captured.toUtc());
      if (age > const Duration(seconds: 30) ||
          age < const Duration(seconds: -5)) {
        return const LocationCapture.unavailable(
            'GPS quá cũ hoặc sai thời gian; hãy lấy vị trí mới.');
      }
    }
    return LocationCapture.available(coordinates);
  }
}

class AttendanceLocationPolicy {
  const AttendanceLocationPolicy(
      {required this.configured,
      required this.required,
      this.maxAccuracyMeters = 50,
      this.maxAgeSeconds = 30});
  final bool configured, required;
  final double maxAccuracyMeters;
  final int maxAgeSeconds;
  factory AttendanceLocationPolicy.fromJson(Map<String, dynamic> value) {
    if (value['configured'] is! bool ||
        value['requireGpsVerification'] is! bool ||
        value['maxAccuracyMeters'] is! num ||
        value['maxAgeSeconds'] is! int) {
      throw const FormatException('Chính sách GPS từ máy chủ không hợp lệ.');
    }
    final accuracy = (value['maxAccuracyMeters'] as num).toDouble();
    final age = value['maxAgeSeconds'] as int;
    if (!accuracy.isFinite || accuracy <= 0 || age < 5 || age > 300) {
      throw const FormatException('Giới hạn GPS từ máy chủ không hợp lệ.');
    }
    return AttendanceLocationPolicy(
        configured: value['configured'] as bool,
        required: value['requireGpsVerification'] as bool,
        maxAccuracyMeters: (value['maxAccuracyMeters'] as num).toDouble(),
        maxAgeSeconds: value['maxAgeSeconds'] as int);
  }
  bool permitsSubmission(GpsCoordinates? gps) {
    if (!required) return true;
    if (!configured ||
        gps == null ||
        !gps.isValid ||
        gps.accuracy == null ||
        !gps.accuracy!.isFinite ||
        gps.accuracy! < 0 ||
        gps.accuracy! > maxAccuracyMeters ||
        gps.capturedAtUtc == null) return false;
    final age = DateTime.now().toUtc().difference(gps.capturedAtUtc!.toUtc());
    return age >= const Duration(seconds: -5) &&
        age <= Duration(seconds: maxAgeSeconds);
  }
}
