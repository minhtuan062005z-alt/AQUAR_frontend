import 'user.dart';

class StaffMember {
  const StaffMember(
      {required this.id,
      required this.name,
      required this.email,
      required this.role,
      required this.active,
      required this.hourlyRate,
      this.managerId,
      this.departmentId,
      this.mustChangePassword = false});
  final int id;
  final String name, email, role;
  final bool active, mustChangePassword;
  final double hourlyRate;
  final int? managerId, departmentId;
  int get roleCode => switch (role) { 'Admin' => 0, 'Manager' => 1, _ => 2 };
  factory StaffMember.fromJson(Map<String, dynamic> value) {
    final user = AquarUser.fromJson(value);
    final rate = value['hourlyRate'];
    if (value['active'] is! bool) {
      throw const FormatException(
          'Trạng thái tài khoản từ máy chủ không hợp lệ.');
    }
    if (rate is! num || !rate.isFinite) {
      throw const FormatException('Đơn giá giờ từ máy chủ không hợp lệ.');
    }
    return StaffMember(
        id: user.id,
        name: user.name,
        email: user.email,
        role: user.role,
        hourlyRate: rate.toDouble(),
        active: value['active'] == true,
        managerId: value['managerId'] as int?,
        departmentId: value['departmentId'] as int?,
        mustChangePassword: value['mustChangePassword'] == true);
  }
}
