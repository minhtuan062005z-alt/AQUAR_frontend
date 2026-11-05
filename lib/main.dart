import 'package:flutter/material.dart';

import 'core/api.dart';
import 'services/aquar_service.dart';
import 'screens/login_page.dart';
import 'screens/change_password_page.dart';

void main() => runApp(const AquarApp());

class AquarApp extends StatefulWidget {
  const AquarApp({super.key, this.api});
  final Api? api;
  @override
  State<AquarApp> createState() => _AquarAppState();
}

class _AquarAppState extends State<AquarApp> {
  final navigator = GlobalKey<NavigatorState>();
  late final api = widget.api ?? Api.instance;
  late final service = AquarService(api: api);
  bool handlingRequiredPassword = false;
  @override
  void initState() {
    super.initState();
    api.authEvent.addListener(onAuthEvent);
  }

  @override
  void dispose() {
    api.authEvent.removeListener(onAuthEvent);
    super.dispose();
  }

  void onAuthEvent() {
    final event = api.authEvent.value;
    if (!mounted) return;
    if (event == null) {
      handlingRequiredPassword = false;
      return;
    }
    if (event == AuthEvent.passwordRequired && handlingRequiredPassword) return;
    handlingRequiredPassword = event == AuthEvent.passwordRequired;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || api.authEvent.value != event) return;
      navigator.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => event == AuthEvent.expired
              ? LoginPage(
                  service: service,
                  message:
                      'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
                )
              : ChangePasswordPage(requiredChange: true, service: service),
        ),
        (_) => false,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigator,
    title: 'AQUAR',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1767C4)),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F8FC),
    ),
    home: LoginPage(service: service),
  );
}
