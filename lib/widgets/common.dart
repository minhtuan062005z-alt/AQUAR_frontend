import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String fmtTime(dynamic raw) {
  if (raw == null) return 'Chưa có';
  final d = DateTime.tryParse('$raw');
  return d == null
      ? '$raw'
      : DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());
}

String fmtMoney(dynamic raw) =>
    '${NumberFormat.decimalPattern('vi').format(num.tryParse('$raw') ?? 0)} đ';
void notice(BuildContext context, String message) {
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const SectionCard({super.key, required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child
          ])));
}
