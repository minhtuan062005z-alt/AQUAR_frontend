import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api.dart';
import '../models/user.dart';
import '../models/staff_member.dart';
import '../services/aquar_service.dart';
import '../services/management_service.dart';
import '../widgets/common.dart';

class PayrollPage extends StatefulWidget {
  const PayrollPage({super.key, required this.user, required this.service});
  final AquarUser user;
  final AquarService service;
  @override
  State<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends State<PayrollPage> {
  late final api = ManagementService(widget.service);
  DateTime period = DateTime.now().toUtc().add(const Duration(hours: 7));
  List<Map<String, dynamic>> rows = [];
  List<StaffMember> staff = [];
  int? selected;
  bool busy = false;
  String? error;
  bool get admin => widget.user.role == 'Admin';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final values = await api.payroll(period.year, period.month);
      final people =
          admin ? await widget.service.staffMembers() : <StaffMember>[];
      if (mounted)
        setState(() {
          rows = values;
          staff = people;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          error = errorText(e);
          rows = [];
        });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> month() async {
    final d = await showDatePicker(
        context: context,
        initialDate: period,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100, 12, 31));
    if (d != null && mounted) {
      setState(() => period = d);
      await load();
    }
  }

  Future<void> configure() async {
    if (busy || selected == null) return;
    setState(() => busy = true);
    try {
      final config = await api.salaryConfiguration(selected!);
      if (!mounted) return;
      await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _PayrollForm(
              api: api,
              staffId: selected!,
              config: config,
              year: period.year,
              month: period.month));
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> calculate() async {
    if (busy || selected == null) return;
    Map<String, dynamic>? existing;
    for (final row in rows) {
      if (row['staffId'] == selected) existing = row;
    }
    if (existing != null && existing['state'] != 'Draft') {
      notice(context, 'Bảng lương đã duyệt/chốt; không được ghi đè.');
      return;
    }
    final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PayrollForm(
            api: api,
            staffId: selected!,
            calculation: true,
            existing: existing,
            year: period.year,
            month: period.month));
    if (changed == true && mounted) await load();
  }

  Future<void> transition(Map<String, dynamic> row, bool close) async {
    if (busy) return;
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(close ? 'Chốt bảng lương?' : 'Duyệt bảng lương?'),
                content: const Text(
                    'Sau khi duyệt, không thể tính lại hoặc sửa bảng lương này. Hãy kiểm tra công thức và dữ liệu trước.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Hủy')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Xác nhận'))
                ]));
    if (yes != true || !mounted || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await api.transition(row['id'] as int, row['version'] as String, close);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && error == null) await load();
  }

  Future<void> export() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final csv = await api.exportPayroll(period.year, period.month);
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('Xuất CSV bảng lương'),
                  content: SingleChildScrollView(child: SelectableText(csv)),
                  actions: [
                    TextButton(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: csv));
                          if (c.mounted) Navigator.pop(c);
                        },
                        child: const Text('Sao chép CSV')),
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('Đóng'))
                  ]));
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(16), children: [
        SectionCard(
            title: 'Bảng lương tháng',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextButton(
                  onPressed: busy ? null : month,
                  child: Text('Tháng ${period.month}/${period.year}')),
              if (admin) ...[
                DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: selected,
                    decoration: const InputDecoration(labelText: 'Nhân viên'),
                    items: [
                      for (final s in staff)
                        DropdownMenuItem(
                            value: s.id,
                            child: Text('${s.name} (${s.email})',
                                overflow: TextOverflow.ellipsis))
                    ],
                    onChanged:
                        busy ? null : (v) => setState(() => selected = v)),
                Wrap(spacing: 8, children: [
                  TextButton(
                      onPressed: busy || selected == null ? null : configure,
                      child: const Text('Cấu hình lương')),
                  TextButton(
                      onPressed: busy || selected == null ? null : calculate,
                      child: const Text('Tính / tính lại')),
                  TextButton(
                      onPressed: busy ? null : export,
                      child: const Text('Xuất CSV'))
                ]),
              ],
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
              TextButton(
                  onPressed: busy ? null : load,
                  child: const Text('Tải lại bảng lương')),
              if (!busy && error == null && rows.isEmpty)
                const Text('Chưa có bảng lương trong phạm vi được phép.'),
              for (final row in rows)
                Card(
                    child: ExpansionTile(
                        title: Text(
                            'Nhân viên #${row['staffId']} • ${stateLabel(row['state'])}'),
                        subtitle: Text('Thực nhận: ${row['netPay']} VND'),
                        childrenPadding: const EdgeInsets.all(12),
                        children: [
                      for (final entry in {
                        'Lương cơ bản': 'monthlySalary',
                        'Ngày chuẩn': 'standardDays',
                        'Giờ/ngày': 'hoursPerDay',
                        'Hệ số OT': 'overtimeMultiplier',
                        'Công thức': 'formula',
                        'Giờ hợp lệ': 'validHours',
                        'Ngày công quy đổi': 'validDays',
                        'Ca chưa đóng': 'openShifts',
                        'Đi muộn (đã ghi nhận)': 'lateCount',
                        'Ngày nghỉ không lương': 'unpaidLeaveDays',
                        'Giờ OT đã duyệt': 'approvedOvertimeHours',
                        'Lương theo công': 'attendancePay',
                        'Tiền OT': 'overtimePay',
                        'Phụ cấp': 'allowances',
                        'Khấu trừ': 'deductions',
                        'Nguồn điều chỉnh': 'inputNote'
                      }.entries)
                        Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                                '${entry.key}: ${row[entry.value] ?? 'Chưa xác định'}')),
                      Text('${row['note']}'),
                      if (admin && row['state'] != 'Closed')
                        TextButton(
                            onPressed: busy
                                ? null
                                : () =>
                                    transition(row, row['state'] == 'Approved'),
                            child: Text(row['state'] == 'Draft'
                                ? 'Duyệt bảng lương'
                                : 'Chốt bảng lương')),
                    ])),
            ])),
      ]);
  static String stateLabel(dynamic value) => switch (value) {
        'Draft' => 'Nháp',
        'Approved' => 'Đã duyệt',
        'Closed' => 'Đã chốt',
        _ => '$value'
      };
}

class _PayrollForm extends StatefulWidget {
  const _PayrollForm(
      {required this.api,
      required this.staffId,
      required this.year,
      required this.month,
      this.config,
      this.existing,
      this.calculation = false});
  final ManagementService api;
  final int staffId, year, month;
  final Map<String, dynamic>? config, existing;
  final bool calculation;
  @override
  State<_PayrollForm> createState() => _PayrollFormState();
}

class _PayrollFormState extends State<_PayrollForm> {
  final form = GlobalKey<FormState>();
  late final labels = widget.calculation
      ? {
          'approvedOvertimeHours': 'Giờ OT đã duyệt (nằm trong giờ chấm công)',
          'allowances': 'Phụ cấp VND',
          'deductions': 'Khấu trừ VND',
          'lateCount': 'Số lần đi muộn (để trống nếu chưa biết)',
          'unpaidLeaveDays': 'Nghỉ không lương (để trống nếu chưa biết)',
          'inputNote': 'Nguồn dữ liệu / căn cứ phê duyệt'
        }
      : {
          'monthlySalary': 'Lương cơ bản tháng VND',
          'standardDays': 'Ngày công tiêu chuẩn (1–31)',
          'hoursPerDay': 'Giờ làm chuẩn/ngày (1–24)',
          'overtimeMultiplier': 'Hệ số OT (1–10)'
        };
  late final fields = {
    for (final key in labels.keys)
      key: TextEditingController(
          text:
              '${(widget.calculation ? widget.existing : widget.config)?[key] ?? (widget.calculation && [
                    'approvedOvertimeHours',
                    'allowances',
                    'deductions'
                  ].contains(key) ? '0' : '')}')
  };
  late String formula = '${widget.config?['formula'] ?? 'EquivalentDays'}';
  late bool managerCanView = widget.config?['managerCanView'] == true;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // Decimal values travel as strings, avoiding binary floating point money.
      final data = <String, dynamic>{
        for (final e in fields.entries) e.key: e.value.text.trim()
      };
      if (widget.calculation) {
        data['year'] = widget.year;
        data['month'] = widget.month;
        data['lateCount'] = fields['lateCount']!.text.trim().isEmpty
            ? null
            : int.parse(fields['lateCount']!.text.trim());
        if (data['unpaidLeaveDays'] == '') data['unpaidLeaveDays'] = null;
        data['version'] = widget.existing?['version'];
        await widget.api.calculate(widget.staffId, data);
      } else {
        data['formula'] = formula;
        data['managerCanView'] = managerCanView;
        data['version'] = widget.config?['version'];
        await widget.api.saveSalary(widget.staffId, data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
          title: Text(widget.calculation
              ? 'Tính lương ${widget.month}/${widget.year}'
              : 'Cấu hình lương #${widget.staffId}'),
          content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                  child: Form(
                      key: form,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        for (final e in labels.entries)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TextFormField(
                                  key: Key('payroll-${e.key}'),
                                  controller: fields[e.key],
                                  enabled: !busy,
                                  maxLength: e.key == 'inputNote' ? 2000 : 20,
                                  decoration:
                                      InputDecoration(labelText: e.value),
                                  keyboardType: e.key == 'inputNote'
                                      ? TextInputType.text
                                      : const TextInputType.numberWithOptions(
                                          decimal: true),
                                  validator: (v) {
                                    final text = v?.trim() ?? '';
                                    if (e.key == 'inputNote') return null;
                                    if (text.isEmpty &&
                                        ['lateCount', 'unpaidLeaveDays']
                                            .contains(e.key)) return null;
                                    if (!RegExp(e.key == 'lateCount'
                                            ? r'^\d+$'
                                            : r'^\d+(\.\d{1,4})?$')
                                        .hasMatch(text))
                                      return 'Nhập số không âm, tối đa 4 số thập phân.';
                                    return null;
                                  })),
                        if (!widget.calculation) ...[
                          DropdownButtonFormField<String>(
                              initialValue: formula,
                              isExpanded: true,
                              items: const [
                                DropdownMenuItem(
                                    value: 'EquivalentDays',
                                    child: Text('Quy đổi giờ / giờ chuẩn')),
                                DropdownMenuItem(
                                    value: 'DailyCapped',
                                    child: Text('Giới hạn tối đa 1 công/ngày'))
                              ],
                              onChanged: busy
                                  ? null
                                  : (v) => setState(() => formula = v!)),
                          SwitchListTile(
                              title: const Text(
                                  'Cho Manager được phân công xem lương'),
                              value: managerCanView,
                              onChanged: busy
                                  ? null
                                  : (v) => setState(() => managerCanView = v)),
                        ],
                        if (error != null)
                          Text(error!,
                              style: const TextStyle(color: Colors.red)),
                      ])))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Hủy')),
            FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? 'Đang lưu...' : 'Lưu'))
          ]));
}
