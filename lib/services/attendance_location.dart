import 'dart:async';
import 'package:geolocator/geolocator.dart';

class GpsCoordinates {
  const GpsCoordinates(this.latitude, this.longitude);
  final double latitude, longitude;
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
    return GpsCoordinates(value.latitude, value.longitude);
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
  static const timeoutMessage =
      'Hết thời gian lấy GPS. Vẫn chấm công, vị trí chưa xác minh.';
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
          'Không lấy được GPS. Vẫn chấm công, vị trí chưa xác minh.');
    } finally {
      expired = true;
    }
  }

  Future<LocationCapture> _attempt(bool Function() expired) async {
    if (!await device.enabled()) {
      return const LocationCapture.unavailable(
          'Dịch vụ định vị đang tắt. Vẫn chấm công, vị trí chưa xác minh.');
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
          'Chưa được cấp quyền vị trí. Vẫn chấm công, vị trí chưa xác minh.');
    }
    final coordinates = await device.position(positionTimeout);
    if (expired()) return const LocationCapture.unavailable(timeoutMessage);
    if (!coordinates.isValid) {
      return const LocationCapture.unavailable(
          'GPS không hợp lệ. Vẫn chấm công, vị trí chưa xác minh.');
    }
    return LocationCapture.available(coordinates);
  }
}
