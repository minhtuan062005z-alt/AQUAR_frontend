import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../models/user.dart';
import '../models/staff_member.dart';
import '../services/aquar_service.dart';
import '../services/management_service.dart';
import '../widgets/common.dart';

class LocationAdministrationPage extends StatefulWidget {
  const LocationAdministrationPage(
      {super.key, required this.user, required this.service});
  final AquarUser user;
  final AquarService service;
  @override
  State<LocationAdministrationPage> createState() =>
      _LocationAdministrationPageState();
}

class _LocationAdministrationPageState
    extends State<LocationAdministrationPage> {
  late final api = ManagementService(widget.service);
  final form = GlobalKey<FormState>();
  final latitude = TextEditingController(),
      longitude = TextEditingController(),
      radius = TextEditingController(),
      accuracy = TextEditingController(),
      age = TextEditingController();
  Map<String, dynamic>? company;
  List<Map<String, dynamic>> alerts = [];
  List<StaffMember> staff = [];
  int? staffId;
  int skip = 0;
  DateTime? from, to;
  String? status = 'OUT_OF_RANGE', companyError, alertError, staffError;
  bool loadingCompany = false,
      loadingAlerts = false,
      saving = false,
      requiredGps = false;
  bool get admin => widget.user.role == 'Admin';
  bool get editable =>
      company?['editable'] == true && !loadingCompany && !saving;
  @override
  void initState() {
    super.initState();
    if (widget.user.canManageStaff) {
      if (admin) loadCompany();
      loadStaff();
      loadAlerts();
    }
  }

  @override
  void dispose() {
    for (final field in [latitude, longitude, radius, accuracy, age]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> loadStaff() async {
    try {
      final values = await widget.service.staffMembers();
      if (mounted)
        setState(() {
          staff = values;
          staffError = null;
        });
    } catch (e) {
      if (mounted) setState(() => staffError = errorText(e));
    }
  }

  Future<void> loadCompany() async {
    if (loadingCompany || saving) return;
    setState(() {
      loadingCompany = true;
      companyError = null;
    });
    try {
      final value = await api.company();
      if (!mounted) return;
      setState(() {
        company = value;
        latitude.text = '${value['latitude'] ?? ''}';
        longitude.text = '${value['longitude'] ?? ''}';
        radius.text = '${value['radiusMeters']}';
        accuracy.text = '${value['maxAccuracyMeters']}';
        age.text = '${value['maxAgeSeconds']}';
        requiredGps = value['requireGpsVerification'] == true;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          companyError = errorText(e);
          company = null;
        });
    } finally {
      if (mounted) setState(() => loadingCompany = false);
    }
  }

  Future<void> saveCompany() async {
    if (!editable || !form.currentState!.validate()) return;
    if (requiredGps && latitude.text.trim().isEmpty) {
      setState(() => companyError =
          'Cần cấu hình tọa độ trước khi bắt buộc xác minh GPS.');
      return;
    }
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Cập nhật chính sách GPS?'),
                content: const Text(
                    'Chính sách mới chỉ áp dụng cho lượt chấm công tiếp theo. Bật bắt buộc sẽ từ chối GPS thiếu, cũ, ngoài phạm vi hoặc không đủ chính xác. Không thay đổi lịch sử cũ.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Hủy')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Xác nhận'))
                ]));
    if (yes != true || !mounted || !editable) return;
    setState(() {
      saving = true;
      companyError = null;
    });
    var success = false;
    try {
      await api.saveCompany({
        'latitude': latitude.text.trim().isEmpty
            ? null
            : double.parse(latitude.text.trim()),
        'longitude': longitude.text.trim().isEmpty
            ? null
            : double.parse(longitude.text.trim()),
        'radiusMeters': double.parse(radius.text.trim()),
        'maxAccuracyMeters': double.parse(accuracy.text.trim()),
        'maxAgeSeconds': int.parse(age.text.trim()),
        'requireGpsVerification': requiredGps,
        'version': company?['version']
      });
      success = true;
    } catch (e) {
      if (mounted) setState(() => companyError = errorText(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
    if (success && mounted) {
      notice(context, 'Đã lưu cấu hình vị trí công ty.');
      await loadCompany();
    }
  }

  Future<void> loadAlerts() async {
    if (loadingAlerts) return;
    setState(() {
      loadingAlerts = true;
      alertError = null;
    });
    try {
      if (from != null && to != null && from!.isAfter(to!))
        throw const FormatException('Ngày bắt đầu phải trước ngày kết thúc.');
      final values = await api.alerts(
          staffId: staffId,
          from: from == null ? null : DateFormat('yyyy-MM-dd').format(from!),
          to: to == null ? null : DateFormat('yyyy-MM-dd').format(to!),
          status: status,
          skip: skip);
      if (mounted) setState(() => alerts = values);
    } catch (e) {
      if (mounted)
        setState(() {
          alertError = errorText(e);
          alerts = [];
        });
    } finally {
      if (mounted) setState(() => loadingAlerts = false);
    }
  }

  Future<void> date(bool first) async {
    final value = await showDatePicker(
        context: context,
        initialDate: (first ? from : to) ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100, 12, 31));
    if (value != null && mounted) {
      setState(() {
        if (first) {
          from = value;
        } else {
          to = value;
        }
        skip = 0;
      });
      await loadAlerts();
    }
  }

  String? coordinate(String? value, bool first) {
    final text = value?.trim() ?? '';
    if (text.isEmpty)
      return (first ? longitude : latitude).text.trim().isEmpty
          ? null
          : 'Cần đủ vĩ độ và kinh độ.';
    final number = double.tryParse(text), limit = first ? 90 : 180;
    return number == null ||
            !number.isFinite ||
            number < -limit ||
            number > limit
        ? 'Tọa độ không hợp lệ.'
        : null;
  }

  String? positive(String? value, double maximum) {
    final n = double.tryParse(value?.trim() ?? '');
    return n == null || !n.isFinite || n <= 0 || n > maximum
        ? 'Nhập số > 0 và ≤ $maximum.'
        : null;
  }

  String time(dynamic value) {
    final raw = '$value';
    final zoned =
        RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(raw);
    final d = DateTime.tryParse(zoned ? raw : '${raw}Z');
    return d == null
        ? 'Chưa có'
        : DateFormat('dd/MM/yyyy HH:mm:ss').format(d.toLocal());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Vị trí công ty và cảnh báo GPS')),
      body: !widget.user.canManageStaff
          ? const Center(child: Text('Bạn không có quyền quản lý GPS.'))
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (admin)
                SectionCard(
                    title: 'Cấu hình vị trí công ty',
                    child: Form(
                        key: form,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (loadingCompany || saving)
                                const LinearProgressIndicator(),
                              if (company != null &&
                                  company!['latitude'] == null)
                                const Text(
                                    'Công ty chưa cấu hình vị trí chấm công.'),
                              if (company != null &&
                                  company!['editable'] != true)
                                const Text(
                                    'Chưa bật cấu hình trong database. Cần xác nhận schema/migration trước khi lưu.'),
                              for (final e in {
                                'Vĩ độ': latitude,
                                'Kinh độ': longitude,
                                'Bán kính cho phép (m)': radius,
                                'Sai số GPS tối đa (m)': accuracy,
                                'Tuổi GPS tối đa (giây)': age
                              }.entries)
                                Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: TextFormField(
                                        key: Key(e.key),
                                        controller: e.value,
                                        enabled: editable,
                                        decoration:
                                            InputDecoration(labelText: e.key),
                                        keyboardType: const TextInputType
                                            .numberWithOptions(
                                            decimal: true, signed: true),
                                        validator: (v) => e.value == latitude
                                            ? coordinate(v, true)
                                            : e.value == longitude
                                                ? coordinate(v, false)
                                                : e.value == radius
                                                    ? positive(v, 100000)
                                                    : e.value == accuracy
                                                        ? positive(v, 10000)
                                                        : (int.tryParse(v?.trim() ??
                                                                            '') ??
                                                                        0) <
                                                                    5 ||
                                                                (int.tryParse(v?.trim() ??
                                                                            '') ??
                                                                        0) >
                                                                    300
                                                            ? 'Nhập số nguyên từ 5 đến 300.'
                                                            : null)),
                              SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                      'Bắt buộc xác minh GPS hợp lệ'),
                                  value: requiredGps,
                                  onChanged: editable
                                      ? (v) => setState(() => requiredGps = v)
                                      : null),
                              const Text(
                                  'Chỉ hợp lệ khi khoảng cách + sai số ≤ bán kính, sai số không vượt giới hạn và GPS còn mới. Không tự lấy vị trí nhân viên làm vị trí công ty.'),
                              Text(
                                  'Cập nhật: ${time(company?['updatedAtUtc'])}'),
                              if (companyError != null)
                                Text(companyError!,
                                    style: const TextStyle(color: Colors.red)),
                              Wrap(spacing: 8, children: [
                                FilledButton(
                                    onPressed: editable ? saveCompany : null,
                                    child: const Text('Lưu cấu hình GPS')),
                                TextButton(
                                    onPressed: loadingCompany || saving
                                        ? null
                                        : loadCompany,
                                    child: const Text('Tải lại cấu hình'))
                              ]),
                            ]))),
              SectionCard(
                  title: 'Cảnh báo ngoài phạm vi',
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (staffError != null) ...[
                          Text(staffError!),
                          TextButton(
                              onPressed: loadStaff,
                              child: const Text('Tải lại nhân viên'))
                        ],
                        DropdownButtonFormField<int>(
                            key: ValueKey('gps-filter-staff-$staffId'),
                            isExpanded: true,
                            initialValue: staffId,
                            decoration:
                                const InputDecoration(labelText: 'Nhân viên'),
                            items: [
                              const DropdownMenuItem<int>(
                                  value: null,
                                  child:
                                      Text('Tất cả trong phạm vi được phép')),
                              for (final s in staff)
                                DropdownMenuItem(
                                    value: s.id,
                                    child: Text('${s.name} (${s.email})',
                                        overflow: TextOverflow.ellipsis))
                            ],
                            onChanged: loadingAlerts
                                ? null
                                : (v) {
                                    setState(() {
                                      staffId = v;
                                      skip = 0;
                                    });
                                    loadAlerts();
                                  }),
                        DropdownButtonFormField<String>(
                            key: ValueKey('gps-filter-status-$status'),
                            initialValue: status,
                            isExpanded: true,
                            decoration:
                                const InputDecoration(labelText: 'Trạng thái'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'OUT_OF_RANGE',
                                  child: Text('Ngoài phạm vi')),
                              DropdownMenuItem<String>(
                                  value: null, child: Text('Tất cả cảnh báo'))
                            ],
                            onChanged: loadingAlerts
                                ? null
                                : (v) {
                                    setState(() {
                                      status = v;
                                      skip = 0;
                                    });
                                    loadAlerts();
                                  }),
                        Wrap(spacing: 8, children: [
                          TextButton(
                              onPressed:
                                  loadingAlerts ? null : () => date(true),
                              child: Text(
                                  'Từ: ${from == null ? 'Tất cả' : DateFormat('dd/MM/yyyy').format(from!)}')),
                          TextButton(
                              onPressed:
                                  loadingAlerts ? null : () => date(false),
                              child: Text(
                                  'Đến: ${to == null ? 'Tất cả' : DateFormat('dd/MM/yyyy').format(to!)}')),
                          TextButton(
                              onPressed: loadingAlerts
                                  ? null
                                  : () {
                                      setState(() {
                                        from = null;
                                        to = null;
                                        staffId = null;
                                        status = 'OUT_OF_RANGE';
                                        skip = 0;
                                      });
                                      loadAlerts();
                                    },
                              child: const Text('Xóa bộ lọc ngày')),
                          TextButton(
                              onPressed: loadingAlerts ? null : loadAlerts,
                              child: const Text('Tải lại cảnh báo'))
                        ]),
                        if (loadingAlerts) const LinearProgressIndicator(),
                        if (alertError != null)
                          Text(alertError!,
                              style: const TextStyle(color: Colors.red)),
                        if (!loadingAlerts &&
                            alertError == null &&
                            alerts.isEmpty)
                          const Text('Không có cảnh báo phù hợp.'),
                        for (final row in alerts)
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              isThreeLine: true,
                              title: Text(
                                  '${row['staffName']} • ${row['eventType'] == 'CheckIn' ? 'Check-in' : 'Check-out'}'),
                              subtitle: Text(
                                  '${time(row['createdAtUtc'])}\nNgoài phạm vi • Khoảng cách: ${row['distanceMeters']} m • Bán kính: ${row['radiusMeters']} m\nGPS: ${row['latitude']}, ${row['longitude']}\nLý do: Vượt bán kính công ty.')),
                        Wrap(spacing: 8, children: [
                          TextButton(
                              onPressed: loadingAlerts || skip == 0
                                  ? null
                                  : () {
                                      setState(() => skip -= 100);
                                      loadAlerts();
                                    },
                              child: const Text('Trang trước')),
                          Text('Trang ${skip ~/ 100 + 1}'),
                          TextButton(
                              onPressed: loadingAlerts || alerts.length < 100
                                  ? null
                                  : () {
                                      setState(() => skip += 100);
                                      loadAlerts();
                                    },
                              child: const Text('Trang sau'))
                        ]),
                        const Text(
                            'Chỉ đọc cảnh báo; không thay đổi lịch sử chấm công.'),
                      ])),
            ]));
}
