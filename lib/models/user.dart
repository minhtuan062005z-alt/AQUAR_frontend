class AquarUser {
  final int id;
  final String name, email, role;
  final bool mustChangePassword;
  const AquarUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.mustChangePassword = false,
  });
  bool get canManageStaff => role == 'Admin' || role == 'Manager';
  factory AquarUser.fromJson(Map<String, dynamic> j) {
    final rawRole = j['role'] ?? j['Role'];
    final role = switch (rawRole.toString().toLowerCase()) {
      '0' || 'admin' => 'Admin',
      '1' || 'manager' => 'Manager',
      '2' || 'employee' => 'Employee',
      _ => throw const FormatException('Vai trò tài khoản không hợp lệ.'),
    };
    return AquarUser(
      id: (j['id'] ?? j['Id']) as int,
      name: '${j['name'] ?? j['Name'] ?? ''}',
      email: '${j['email'] ?? j['Email'] ?? ''}',
      role: role,
      mustChangePassword:
          j['mustChangePassword'] == true || j['MustChangePassword'] == true,
    );
  }
}
