import 'package:flutter/material.dart';

import '../core/api.dart';

import '../models/user.dart';
import '../services/aquar_service.dart';
import 'login_page.dart';
import 'change_password_page.dart';
import 'attendance_page.dart';
import 'staff_page.dart';
import 'report_page.dart';

class HomePage extends StatefulWidget {
  final AquarUser user;
  final AquarService? service;
  const HomePage({super.key, required this.user, this.service});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selected = 0;
  bool signingOut = false;
  late final service = widget.service ?? AquarService();
  @override
  Widget build(BuildContext context) {
    final elevated = widget.user.canManageStaff;
    final pages = <Widget>[
      AttendancePage(user: widget.user, service: service),
      ReportPage(user: widget.user, service: service),
      if (elevated) StaffPage(user: widget.user, service: service),
    ];
    final items = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.access_time),
        label: 'Chấm công',
      ),
      const NavigationDestination(
        icon: Icon(Icons.bar_chart),
        label: 'Báo cáo',
      ),
      if (elevated)
        const NavigationDestination(
          icon: Icon(Icons.groups),
          label: 'Nhân viên',
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('AQUAR • ${widget.user.name}'),
        actions: [
          IconButton(
            tooltip: 'Cài đặt tài khoản',
            icon: const Icon(Icons.manage_accounts),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChangePasswordPage(service: service),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: signingOut
                ? null
                : () async {
                    setState(() => signingOut = true);
                    try {
                      await service.logout();
                      if (context.mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LoginPage(service: service),
                          ),
                          (_) => false,
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(errorText(e))));
                      }
                    } finally {
                      if (mounted) setState(() => signingOut = false);
                    }
                  },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: pages[selected],
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (v) => setState(() => selected = v),
        destinations: items,
      ),
    );
  }
}
