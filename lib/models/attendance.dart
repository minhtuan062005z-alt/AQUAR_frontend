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
      this.radiusMeters,
      this.accuracy,
      this.verificationStatus,
      this.method,
      required this.status,
      this.verificationReason});
  final double? latitude, longitude, distanceMeters;
  final double? radiusMeters, accuracy;
  final String? verificationStatus, method;
  final String status;
  final String? verificationReason;
  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude! >= -90 &&
      latitude! <= 90 &&
      longitude! >= -180 &&
      longitude! <= 180;
  String get result =>
      verificationStatus ??
      (verificationReason == 'CompanyNotConfigured'
          ? 'NOT_CONFIGURED'
          : !hasCoordinates
              ? 'NOT_VERIFIED'
              : switch (status) {
                  'InRange' || 'VERIFIED' => 'VERIFIED',
                  'OutOfRange' || 'OUT_OF_RANGE' => 'OUT_OF_RANGE',
                  'LOW_ACCURACY' ||
                  'GPS_UNAVAILABLE' ||
                  'NOT_CONFIGURED' =>
                    status,
                  _ => 'NOT_VERIFIED'
                });
  bool get isVerified => result == 'VERIFIED' || result == 'OUT_OF_RANGE';
  bool get isOutside => result == 'OUT_OF_RANGE';
  String get statusLabel => switch (result) {
        'VERIFIED' => 'Trong phạm vi công ty',
        'OUT_OF_RANGE' => 'Ngoài phạm vi công ty',
        'LOW_ACCURACY' => 'GPS không đủ độ chính xác',
        'GPS_UNAVAILABLE' => 'Không lấy được GPS',
        _ => 'Chưa xác minh vị trí',
      };
  String get reasonLabel => switch (verificationReason) {
        'CompanyNotConfigured' => 'Công ty chưa cấu hình vị trí chấm công.',
        'NoGps' => 'Không có GPS tại thời điểm chấm công.',
        'MissingAccuracy' => 'Thiết bị chưa gửi độ chính xác GPS.',
        'MissingCaptureTime' => 'Chưa có thời điểm lấy GPS.',
        'StaleOrFuturePosition' => 'Vị trí quá cũ hoặc sai thời gian.',
        'AccuracyAboveLimit' => 'Độ chính xác GPS vượt giới hạn công ty.',
        'AccuracyOverlapsBoundary' =>
          'Vùng sai số GPS giao với ranh giới công ty.',
        'OutsideCompanyRadius' => 'Khoảng cách vượt bán kính cho phép.',
        'ClientCoordinatesCompared' =>
          'Backend đã tính khoảng cách theo cấu hình lúc chấm công.',
        _ => result == 'NOT_CONFIGURED'
            ? 'Công ty chưa cấu hình vị trí chấm công.'
            : result == 'NOT_VERIFIED'
                ? 'Bản ghi cũ hoặc chưa có kết quả xác minh.'
                : '',
      };
  double? get displayedDistance => hasCoordinates &&
          (isVerified ||
              verificationStatus != null &&
                  (result == 'LOW_ACCURACY' || result == 'NOT_VERIFIED'))
      ? distanceMeters
      : null;
  static AttendanceLocationInfo? fromJson(Object? value) {
    if (value is! Map) return null;
    double? number(Object? raw) =>
        raw is num && raw.isFinite ? raw.toDouble() : null;
    final distance = number(value['distanceMeters']);
    return AttendanceLocationInfo(
        latitude: number(value['latitude']),
        longitude: number(value['longitude']),
        distanceMeters: distance != null && distance >= 0 ? distance : null,
        radiusMeters: number(value['radiusMeters']),
        accuracy: number(value['accuracy']),
        verificationStatus: value['verificationStatus'] as String?,
        method: value['method'] as String?,
        status: value['status'] is String
            ? value['status'] as String
            : 'Unverified',
        verificationReason: value['verificationReason'] is String
            ? value['verificationReason'] as String
            : null);
  }
}
