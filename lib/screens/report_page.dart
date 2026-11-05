import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../models/user.dart';
import '../models/staff_member.dart';
import '../services/aquar_service.dart';
import '../widgets/common.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key, required this.user, this.service});
  final AquarUser user;
  final AquarService? service;
  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  late final service = widget.service ?? AquarService();
  late int selectedId = widget.user.id;
  String period = 'month';
  DateTime selectedDate = DateTime.now().toUtc().add(const Duration(hours: 7));
  bool busy = false, loadingStaff = false;
  List<StaffMember> staff = [];
  Map<String, dynamic>? result;
  String? error, staffError, emailConfirmation;
  static const periods = {
    'week': 'Tuần',
    'month': 'Tháng',
    'quarter': 'Quý',
    'year': 'Năm'
  };
  @override
  void initState() {
    super.initState();
    if (widget.user.canManageStaff) loadStaff();
  }

  Future<void> loadStaff() async {
    setState(() {
      loadingStaff = true;
      staffError = null;
    });
    try {
      final values = await service.staffMembers();
      if (mounted) setState(() => staff = values);
    } catch (failure) {
      if (mounted) setState(() => staffError = errorText(failure));
    } finally {
      if (mounted) setState(() => loadingStaff = false);
    }
  }

  Future<void> date() async {
    final value = await showDatePicker(
        context: context,
        initialDate:
            DateTime(selectedDate.year, selectedDate.month, selectedDate.day),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100));
    if (value != null && mounted) {
      setState(() {
        selectedDate = value;
        result = null;
        error = null;
        emailConfirmation = null;
      });
    }
  }

  Future<void> load({bool email = false}) async {
    if (busy) return;
    final id = selectedId;
    setState(() {
      busy = true;
      error = null;
      emailConfirmation = null;
    });
    try {
      final report = email && result != null
          ? result!
          : await service.statistics(
              id, period, DateFormat('yyyy-MM-dd').format(selectedDate));
      final from = DateTime.tryParse('${report['from']}'),
          to = DateTime.tryParse('${report['to']}');
      if (report['staffId'] != id ||
          report['hours'] is! num ||
          report['grossSalary'] is! num ||
          report['shifts'] is! int ||
          from == null ||
          to == null) {
        throw const FormatException('Dữ liệu báo cáo từ máy chủ không hợp lệ.');
      }
      if (!mounted) return;
      setState(() => result = report);
      if (email) {
        final recipient = await service.emailReport(id, from, to);
        if (mounted) {
          setState(() =>
              emailConfirmation = 'SMTP đã nhận báo cáo gửi đến $recipient.');
        }
      }
    } catch (failure) {
      if (mounted) setState(() => error = errorText(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = <int, String>{
      widget.user.id: '${widget.user.name} (của tôi)'
    };
    for (final person in staff) {
      people.putIfAbsent(person.id, () => '${person.name} (${person.email})');
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      SectionCard(
          title: 'Báo cáo và lương dự kiến',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.user.canManageStaff) ...[
              DropdownButtonFormField<int>(
                  isExpanded: true,
                  key: const Key('report-person'),
                  initialValue: selectedId,
                  decoration: const InputDecoration(labelText: 'Báo cáo cho'),
                  items: [
                    for (final entry in people.entries)
                      DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value,
                              overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: busy || loadingStaff
                      ? null
                      : (v) => setState(() {
                            selectedId = v!;
                            result = null;
                            error = null;
                            emailConfirmation = null;
                          })),
              if (loadingStaff) const LinearProgressIndicator(),
              if (staffError != null) ...[
                Text(staffError!),
                TextButton(
                    onPressed: loadingStaff || busy ? null : loadStaff,
                    child: const Text('Tải lại nhân viên'))
              ],
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: period,
                decoration: const InputDecoration(labelText: 'Kỳ thống kê'),
                items: [
                  for (final entry in periods.entries)
                    DropdownMenuItem(
                        value: entry.key, child: Text(entry.value)),
                ],
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                          period = v!;
                          result = null;
                          error = null;
                          emailConfirmation = null;
                        })),
            TextButton.icon(
                onPressed: busy ? null : date,
                icon: const Icon(Icons.calendar_month),
                label: Text(
                    'Ngày trong kỳ: ${DateFormat('dd/MM/yyyy').format(selectedDate)}')),
            const Text(
                'Kỳ báo cáo do Backend xác định theo UTC+7. Tuần bắt đầu thứ Hai.'),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(
                  onPressed: busy ? null : () => load(),
                  child: const Text('Xem báo cáo')),
              OutlinedButton.icon(
                  onPressed: busy ? null : () => load(email: true),
                  icon: const Icon(Icons.mail_outline),
                  label: const Text('Gửi email'))
            ]),
            if (busy)
              const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator()),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child:
                      Text(error!, style: const TextStyle(color: Colors.red))),
            if (emailConfirmation != null)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(emailConfirmation!,
                      key: const Key('email-confirmation'))),
            if (result != null) ...[
              const Divider(height: 32),
              Text('Số ca: ${result!['shifts']}'),
              Text('Tổng giờ: ${result!['hours']}'),
              Text('Lương gộp dự kiến: ${fmtMoney(result!['grossSalary'])}'),
              const SizedBox(height: 8),
              Text('${result!['note'] ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall)
            ],
          ]))
    ]);
  }
}
