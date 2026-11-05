import 'package:flutter/material.dart';

import '../core/api.dart';
import '../services/aquar_service.dart';
import 'home_page.dart';
import 'change_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.service, this.message});
  final AquarService? service;
  final String? message;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;
  String error = '';
  late final service = widget.service ?? AquarService();
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Vui lòng nhập email và mật khẩu.');
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) {
      setState(() {
        busy = false;
        error = 'Email không hợp lệ.';
      });
      return;
    }
    try {
      final user = await service.login(email.text, password.text);
      password.clear();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => user.mustChangePassword
                ? ChangePasswordPage(requiredChange: true, service: service)
                : HomePage(user: user, service: service),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = errorText(e, login: true));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.fingerprint,
                    size: 64,
                    color: Color(0xFF1767C4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'AQUAR',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const Text('Hệ thống chấm công nhân viên'),
                  if (widget.message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(widget.message!),
                    ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(error, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: busy ? null : submit,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(busy ? 'Đang đăng nhập...' : 'Đăng nhập'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
