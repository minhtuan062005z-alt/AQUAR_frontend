import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../services/aquar_service.dart';
import 'login_page.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({
    super.key,
    this.requiredChange = false,
    this.service,
  });
  final bool requiredChange;
  final AquarService? service;
  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final current = TextEditingController(),
      next = TextEditingController(),
      confirm = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false;
  String error = '';
  late final service = widget.service ?? AquarService();
  @override
  void dispose() {
    current.dispose();
    next.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await service.changePassword(current.text, next.text, confirm.text);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LoginPage(
            service: service,
            message: 'Đã đổi mật khẩu. Vui lòng đăng nhập lại.',
          ),
        ),
        (_) => false,
      );
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> signOut() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await service.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LoginPage(service: service)),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !widget.requiredChange && !busy,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Đổi mật khẩu'),
            automaticallyImplyLeading: !widget.requiredChange,
            actions: [
              if (widget.requiredChange)
                IconButton(
                  tooltip: 'Đăng xuất',
                  onPressed: busy ? null : signOut,
                  icon: const Icon(Icons.logout),
                ),
            ],
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: form,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.requiredChange
                                ? 'Bạn cần đổi mật khẩu tạm thời trước khi sử dụng ứng dụng.'
                                : 'Nhập mật khẩu hiện tại và mật khẩu mới.',
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: current,
                            enabled: !busy,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              labelText: 'Mật khẩu hiện tại',
                            ),
                            validator: (v) => v == null || v.isEmpty
                                ? 'Nhập mật khẩu hiện tại.'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: next,
                            enabled: !busy,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              labelText: 'Mật khẩu mới',
                            ),
                            validator: (v) {
                              if (v == null || v.length < 12) {
                                return 'Mật khẩu cần ít nhất 12 ký tự.';
                              }
                              if (utf8.encode(v).length > 72 ||
                                  v.contains('\u0000')) {
                                return 'Mật khẩu tối đa 72 byte UTF-8, không chứa NUL.';
                              }
                              if (v == current.text) {
                                return 'Mật khẩu mới phải khác mật khẩu hiện tại.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: confirm,
                            enabled: !busy,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              labelText: 'Xác nhận mật khẩu mới',
                            ),
                            validator: (v) =>
                                v == null || v.isEmpty || v != next.text
                                    ? 'Xác nhận mật khẩu không khớp.'
                                    : null,
                            onFieldSubmitted: (_) => submit(),
                          ),
                          if (error.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                error,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: busy ? null : submit,
                              child:
                                  Text(busy ? 'Đang lưu...' : 'Lưu mật khẩu'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
