import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../models/user.dart';
import '../models/staff_member.dart';
import '../services/aquar_service.dart';
import '../widgets/common.dart';

class StaffPage extends StatefulWidget {
  const StaffPage({super.key, required this.user, this.service});
  final AquarUser user;
  final AquarService? service;
  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> {
  late final service = widget.service ?? AquarService();
  late Future<List<StaffMember>> data;
  final updating = <int>{};
  bool opening = false;
  @override
  void initState() {
    super.initState();
    data =
        widget.user.canManageStaff ? service.staffMembers() : Future.value([]);
  }

  void reload() => setState(() => data = service.staffMembers());
  Future<void> refresh() async {
    reload();
    try {
      await data;
    } on Object {/* FutureBuilder renders retryable error. */}
  }

  bool get admin => widget.user.role == 'Admin';

  Future<void> editor([StaffMember? person]) async {
    if (!admin || opening) return;
    setState(() => opening = true);
    try {
      final staff = await service.staffMembers();
      final departments = await service.departments();
      if (!mounted) return;
      final saved = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _StaffEditor(
              service: service,
              staff: staff,
              departments: departments,
              existing: person));
      if (saved == true && mounted) {
        reload();
        notice(
            context,
            person == null
                ? 'Đã tạo tài khoản với mật khẩu tạm thời.'
                : 'Đã cập nhật nhân viên.');
      }
    } catch (error) {
      if (mounted) notice(context, errorText(error));
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> toggle(StaffMember person) async {
    if (!admin || updating.contains(person.id)) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title:
                    Text(person.active ? 'Khóa tài khoản?' : 'Mở tài khoản?'),
                content: Text('${person.name} (${person.email})'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('Hủy')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('Xác nhận')),
                ]));
    if (confirmed != true || !mounted || updating.contains(person.id)) return;
    setState(() => updating.add(person.id));
    try {
      await service.setStaffActive(person.id, !person.active);
      if (mounted) {
        reload();
        notice(context, 'Đã cập nhật trạng thái tài khoản.');
      }
    } catch (error) {
      if (mounted) notice(context, errorText(error));
    } finally {
      if (mounted) setState(() => updating.remove(person.id));
    }
  }

  Future<void> manual(StaffMember person) async {
    if (!widget.user.canManageStaff) return;
    final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ManualDialog(service: service, person: person));
    if (saved == true && mounted) notice(context, 'Đã ghi nhận ca thủ công.');
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.canManageStaff) {
      return const Center(child: Text('Bạn không có quyền quản lý nhân viên.'));
    }
    return RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (admin)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FilledButton.icon(
                        onPressed: opening ? null : () => editor(),
                        icon: const Icon(Icons.person_add),
                        label: Text(opening
                            ? 'Đang tải...'
                            : 'Thêm nhân viên / quản lý'))),
              SectionCard(
                  title: 'Danh sách nhân viên',
                  child: FutureBuilder<List<StaffMember>>(
                      future: data,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(errorText(snapshot.error!)),
                                TextButton(
                                    onPressed: reload,
                                    child: const Text('Thử lại'))
                              ]);
                        }
                        final rows = snapshot.data ?? [];
                        if (rows.isEmpty) {
                          return Text(admin
                              ? 'Chưa có nhân viên.'
                              : 'Chưa có nhân viên được gán cho bạn. Admin cần thiết lập người quản lý.');
                        }
                        return Column(children: [
                          for (final person in rows)
                            ListTile(
                                key: ValueKey('staff-${person.id}'),
                                contentPadding: EdgeInsets.zero,
                                title: Text(person.name),
                                subtitle: Text(
                                    '${person.email}\n${person.role} • ${person.active ? 'Hoạt động' : 'Đã khóa'} • ${fmtMoney(person.hourlyRate)}/giờ'),
                                isThreeLine: true,
                                trailing: updating.contains(person.id)
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator())
                                    : PopupMenuButton<String>(
                                        onSelected: (action) {
                                          if (action == 'edit') editor(person);
                                          if (action == 'manual')
                                            manual(person);
                                          if (action == 'toggle')
                                            toggle(person);
                                        },
                                        itemBuilder: (_) => [
                                              if (admin)
                                                const PopupMenuItem(
                                                    value: 'edit',
                                                    child: Text(
                                                        'Sửa thông tin / phân công')),
                                              if (person.active)
                                                const PopupMenuItem(
                                                    value: 'manual',
                                                    child: Text(
                                                        'Chấm công thủ công')),
                                              if (admin &&
                                                  person.id != widget.user.id)
                                                PopupMenuItem(
                                                    value: 'toggle',
                                                    child: Text(person.active
                                                        ? 'Khóa tài khoản'
                                                        : 'Mở tài khoản')),
                                            ]))
                        ]);
                      })),
            ]));
  }
}

class _StaffEditor extends StatefulWidget {
  const _StaffEditor(
      {required this.service,
      required this.staff,
      required this.departments,
      this.existing});
  final AquarService service;
  final List<StaffMember> staff;
  final List<Map<String, dynamic>> departments;
  final StaffMember? existing;
  @override
  State<_StaffEditor> createState() => _StaffEditorState();
}

class _StaffEditorState extends State<_StaffEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late final email = TextEditingController(text: widget.existing?.email ?? '');
  final password = TextEditingController();
  late final rate =
      TextEditingController(text: widget.existing?.hourlyRate.toString() ?? '');
  late int role = widget.existing?.roleCode ?? 2;
  late int? managerId = widget.existing?.managerId,
      departmentId = widget.existing?.departmentId;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    rate.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final existing = widget.existing;
      if (existing == null) {
        await widget.service.addStaff(
            name: name.text.trim(),
            email: email.text.trim(),
            password: password.text,
            role: role,
            hourlyRate: double.parse(rate.text.trim()),
            managerId: managerId,
            departmentId: departmentId);
      } else {
        await widget.service.updateStaff(existing.id, {
          'name': name.text.trim(),
          'email': email.text.trim(),
          'role': role,
          'hourlyRate': double.parse(rate.text.trim()),
          'managerId': managerId,
          'departmentId': departmentId,
          'active': existing.active
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) setState(() => error = errorText(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final managers = widget.staff
        .where((s) =>
            s.id != widget.existing?.id &&
            s.role == 'Manager' &&
            (s.active || s.id == managerId))
        .toList();
    final departmentExists =
        widget.departments.any((d) => d['id'] == departmentId);
    return PopScope(
        canPop: !busy,
        child: AlertDialog(
            title: Text(
                widget.existing == null ? 'Thêm tài khoản' : 'Sửa nhân viên'),
            content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                    child: Form(
                        key: form,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          TextFormField(
                              key: const Key('staff-name'),
                              controller: name,
                              enabled: !busy,
                              decoration:
                                  const InputDecoration(labelText: 'Họ tên'),
                              validator: (v) => v == null ||
                                      v.trim().isEmpty ||
                                      v.trim().length > 200
                                  ? 'Nhập họ tên hợp lệ, tối đa 200 ký tự.'
                                  : null),
                          const SizedBox(height: 12),
                          TextFormField(
                              key: const Key('staff-email'),
                              controller: email,
                              enabled: !busy,
                              keyboardType: TextInputType.emailAddress,
                              decoration:
                                  const InputDecoration(labelText: 'Email'),
                              validator: (v) => v == null ||
                                      v.trim().length > 254 ||
                                      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                          .hasMatch(v.trim())
                                  ? 'Email không hợp lệ.'
                                  : null),
                          if (widget.existing == null) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                                key: const Key('staff-password'),
                                controller: password,
                                enabled: !busy,
                                obscureText: true,
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: const InputDecoration(
                                    labelText:
                                        'Mật khẩu tạm (ít nhất 12 ký tự)'),
                                validator: (v) => v == null ||
                                        v.length < 12 ||
                                        utf8.encode(v).length > 72 ||
                                        v.contains('\u0000')
                                    ? 'Mật khẩu cần ít nhất 12 ký tự, tối đa 72 byte UTF-8.'
                                    : null),
                            const Text(
                                'Nhân viên phải đổi mật khẩu khi đăng nhập lần đầu.'),
                          ],
                          const SizedBox(height: 12),
                          TextFormField(
                              key: const Key('staff-rate'),
                              controller: rate,
                              enabled: !busy,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'Lương/giờ (VND)',
                                  hintText: 'Ví dụ: 30000 hoặc 30000.5'),
                              validator: (v) {
                                final value = double.tryParse(v?.trim() ?? '');
                                return value == null ||
                                        !value.isFinite ||
                                        value < 0 ||
                                        value > 1000000000
                                    ? 'Nhập đơn giá từ 0 đến 1000000000, dùng dấu chấm thập phân.'
                                    : null;
                              }),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                              isExpanded: true,
                              key: const Key('staff-role'),
                              initialValue: role,
                              decoration:
                                  const InputDecoration(labelText: 'Vai trò'),
                              items: [
                                if (widget.existing?.role == 'Admin')
                                  const DropdownMenuItem(
                                      value: 0, child: Text('Admin')),
                                const DropdownMenuItem(
                                    value: 2, child: Text('Employee')),
                                const DropdownMenuItem(
                                    value: 1, child: Text('Manager')),
                              ],
                              onChanged:
                                  busy || widget.existing?.role == 'Admin'
                                      ? null
                                      : (v) => setState(() {
                                            role = v!;
                                            if (role != 2) managerId = null;
                                          })),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                              isExpanded: true,
                              key: const Key('staff-manager'),
                              initialValue: managerId,
                              decoration: const InputDecoration(
                                  labelText: 'Người quản lý'),
                              items: [
                                const DropdownMenuItem<int>(
                                    value: null, child: Text('Chưa phân công')),
                                for (final manager in managers)
                                  DropdownMenuItem(
                                      value: manager.id,
                                      child: Text(
                                          '${manager.name}${manager.active ? '' : ' (đã khóa)'}')),
                              ],
                              onChanged: busy || role != 2
                                  ? null
                                  : (v) => setState(() => managerId = v)),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                              isExpanded: true,
                              key: const Key('staff-department'),
                              initialValue: departmentId,
                              decoration:
                                  const InputDecoration(labelText: 'Phòng ban'),
                              items: [
                                const DropdownMenuItem<int>(
                                    value: null,
                                    child: Text('Chưa phân phòng ban')),
                                if (departmentId != null && !departmentExists)
                                  DropdownMenuItem(
                                      value: departmentId,
                                      child: Text(
                                          'Phòng ban hiện tại #$departmentId')),
                                for (final department in widget.departments)
                                  DropdownMenuItem(
                                      value: department['id'] as int,
                                      child: Text('${department['name']}')),
                              ],
                              onChanged: busy
                                  ? null
                                  : (v) => setState(() => departmentId = v)),
                          if (error != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(error!,
                                    style: const TextStyle(color: Colors.red))),
                        ])))),
            actions: [
              TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context, false),
                  child: const Text('Hủy')),
              FilledButton(
                  onPressed: busy ? null : save,
                  child: Text(busy ? 'Đang lưu...' : 'Lưu'))
            ]));
  }
}

class _ManualDialog extends StatefulWidget {
  const _ManualDialog({required this.service, required this.person});
  final AquarService service;
  final StaffMember person;
  @override
  State<_ManualDialog> createState() => _ManualDialogState();
}

class _ManualDialogState extends State<_ManualDialog> {
  final reason = TextEditingController();
  DateTime end = DateTime.now(),
      start = DateTime.now().subtract(const Duration(hours: 8));
  bool busy = false;
  String? error;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> pick(bool first) async {
    final initial = first ? start : end;
    final date = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime.now());
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null || !mounted) return;
    setState(() {
      final value =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
      if (first) {
        start = value;
      } else {
        end = value;
      }
    });
  }

  Future<void> save() async {
    if (busy) return;
    if (reason.text.trim().isEmpty ||
        !end.isAfter(start) ||
        end.difference(start) > const Duration(hours: 24) ||
        end.isAfter(DateTime.now())) {
      setState(() =>
          error = 'Nhập lý do và ca hợp lệ, tối đa 24 giờ, không ở tương lai.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.service
          .manualAttendance(widget.person.id, start, end, reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) setState(() => error = errorText(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
          title: Text('Chấm công: ${widget.person.name}'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                title: const Text('Giờ vào'),
                subtitle: Text(fmtTime(start.toIso8601String())),
                trailing: const Icon(Icons.edit),
                onTap: busy ? null : () => pick(true)),
            ListTile(
                title: const Text('Giờ ra'),
                subtitle: Text(fmtTime(end.toIso8601String())),
                trailing: const Icon(Icons.edit),
                onTap: busy ? null : () => pick(false)),
            TextField(
                controller: reason,
                enabled: !busy,
                maxLength: 2000,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Lý do bắt buộc')),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
          ])),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context, false),
                child: const Text('Hủy')),
            FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? 'Đang lưu...' : 'Ghi nhận'))
          ]));
}
