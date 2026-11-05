class Attendance {
  const Attendance(
      {required this.id,
      required this.staffId,
      required this.checkInUtc,
      this.checkOutUtc,
      required this.method,
      required this.manual,
      this.checkInLocation,
      this.checkOutLocation});
  final int id, staffId;
  final DateTime checkInUtc;
  final DateTime? checkOutUtc;
  final String method;
  final bool manual;
  final AttendanceLocationInfo? checkInLocation, checkOutLocation;
  bool get isOpen => checkOutUtc == null;

  factory Attendance.fromJson(Map<String, dynamic> json) {
    DateTime utc(Object? value) {
      if (value is! String) {
        throw const FormatException('Thời gian chấm công không hợp lệ.');
      }
      // SQL datetime2 may serialize without Z, but these API fields are explicitly UTC.
      final zoned = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false)
          .hasMatch(value);
      final parsed = DateTime.tryParse(zoned ? value : '${value}Z');
      if (parsed == null) {
        throw const FormatException('Thời gian chấm công không hợp lệ.');
      }
      return parsed.toUtc();
    }

    if (json['id'] is! int || json['staffId'] is! int) {
      throw const FormatException('Bản ghi chấm công không hợp lệ.');
    }
    final start = utc(json['checkInUtc']);
    final end = json['checkOutUtc'] == null ? null : utc(json['checkOutUtc']);
    if (end != null && end.isBefore(start)) {
      throw const FormatException('Giờ ra trước giờ vào.');
    }
    return Attendance(
        id: json['id'] as int,
        staffId: json['staffId'] as int,
        checkInUtc: start,
        checkOutUtc: end,
        method: '${json['method'] ?? ''}',
        manual: json['manual'] == true,
        checkInLocation:
            AttendanceLocationInfo.fromJson(json['checkInLocation']),
        checkOutLocation:
            AttendanceLocationInfo.fromJson(json['checkOutLocation']));
  }
}

class AttendanceLocationInfo {
  const AttendanceLocationInfo(
      {this.latitude,
      this.longitude,
      this.distanceMeters,
      required this.status,
      this.verificationReason});
  final double? latitude, longitude, distanceMeters;
  final String status;
  final String? verificationReason;
  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude! >= -90 &&
      latitude! <= 90 &&
      longitude! >= -180 &&
      longitude! <= 180;
  bool get isVerified =>
      hasCoordinates &&
      verificationReason != 'CompanyNotConfigured' &&
      (status == 'InRange' || status == 'OutOfRange');
  bool get isOutside => isVerified && status == 'OutOfRange';
  String get statusLabel => !isVerified
      ? 'Chưa xác minh vị trí'
      : isOutside
          ? 'Ngoài phạm vi công ty'
          : 'Trong phạm vi công ty';
  double? get displayedDistance => isVerified ? distanceMeters : null;
  static AttendanceLocationInfo? fromJson(Object? value) {
    if (value is! Map) return null;
    double? number(Object? raw) =>
        raw is num && raw.isFinite ? raw.toDouble() : null;
    final distance = number(value['distanceMeters']);
    return AttendanceLocationInfo(
        latitude: number(value['latitude']),
        longitude: number(value['longitude']),
        distanceMeters: distance != null && distance >= 0 ? distance : null,
        status: value['status'] is String
            ? value['status'] as String
            : 'Unverified',
        verificationReason: value['verificationReason'] is String
            ? value['verificationReason'] as String
            : null);
  }
}
