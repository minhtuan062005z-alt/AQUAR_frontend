import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquar_app/core/api.dart';
import 'package:aquar_app/main.dart';
import 'package:aquar_app/models/user.dart';
import 'package:aquar_app/screens/change_password_page.dart';
import 'package:aquar_app/services/aquar_service.dart';

class MemoryTokens implements TokenStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async {
    value = token;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.reply);
  final ResponseBody Function(RequestOptions) reply;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => reply(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody jsonReply(Object data, [int status = 200]) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
Api fakeApi(MemoryTokens tokens, ResponseBody Function(RequestOptions) reply) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
  dio.httpClientAdapter = FakeAdapter(reply);
  return Api(client: dio, tokens: tokens);
}

void main() {
  for (final role in ['Admin', 'Manager', 'Employee', 0, 1, 2]) {
    test('Parse role $role', () {
      final user = AquarUser.fromJson({'id': 1, 'role': role});
      expect(user.canManageStaff, role != 'Employee' && role != 2);
    });
  }
  test('Login parses top-level password flag and stores session', () async {
    final tokens = MemoryTokens();
    final api = fakeApi(tokens, (request) {
      expect(request.path, '/api/auth/login');
      expect((request.data as Map)['email'], 'person@example.invalid');
      return jsonReply({
        'token': 'test-session',
        'mustChangePassword': true,
        'user': {
          'id': 1,
          'name': 'Test',
          'email': 'person@example.invalid',
          'role': 'Employee',
        },
      });
    });
    final user = await AquarService(api: api)
        .login(' person@example.invalid ', 'test-only-password');
    expect(user.mustChangePassword, isTrue);
    expect(tokens.value, 'test-session');
  });
  test('Unknown role is rejected before storing JWT', () async {
    final tokens = MemoryTokens();
    final api = fakeApi(
      tokens,
      (_) => jsonReply({
        'token': 'test-session',
        'user': {'id': 1, 'role': 'Unknown'},
      }),
    );
    await expectLater(
      AquarService(api: api)
          .login('person@example.invalid', 'test-only-password'),
      throwsFormatException,
    );
    expect(tokens.value, isNull);
  });
  test('Password API sends all three fields then clears JWT', () async {
    final tokens = MemoryTokens()..value = 'test-session';
    final api = fakeApi(tokens, (request) {
      expect(request.method, 'PUT');
      expect(request.path, '/api/account/password');
      expect(request.headers['Authorization'], 'Bearer test-session');
      expect(request.data, {
        'currentPassword': 'old-test-value',
        'newPassword': 'new-test-value',
        'confirmNewPassword': 'new-test-value',
      });
      return jsonReply({'message': 'OK'});
    });
    await AquarService(api: api)
        .changePassword('old-test-value', 'new-test-value', 'new-test-value');
    expect(tokens.value, isNull);
  });
  test('Failed password change retains session and error', () async {
    final tokens = MemoryTokens()..value = 'test-session';
    final api = fakeApi(
      tokens,
      (_) => jsonReply({'message': 'Mật khẩu hiện tại không đúng.'}, 400),
    );
    await expectLater(
      AquarService(api: api)
          .changePassword('wrong', 'new-test-value', 'new-test-value'),
      throwsA(isA<DioException>()),
    );
    expect(tokens.value, isNotNull);
  });
  for (final status in [401, 403]) {
    test('Protected request handles $status', () async {
      final tokens = MemoryTokens()..value = 'test-session';
      final api = fakeApi(
        tokens,
        (_) => jsonReply({'code': 'MUST_CHANGE_PASSWORD'}, status),
      );
      await expectLater(api.dio.get('/api/me'), throwsA(isA<DioException>()));
      expect(
        api.authEvent.value,
        status == 401 ? AuthEvent.expired : AuthEvent.passwordRequired,
      );
      expect(tokens.value, status == 401 ? isNull : isNotNull);
    });
  }
  test('Normal forbidden response does not log out', () async {
    final tokens = MemoryTokens()..value = 'test-session';
    final api = fakeApi(tokens, (_) => jsonReply({}, 403));
    await expectLater(
      api.dio.get('/api/accounts'),
      throwsA(isA<DioException>()),
    );
    expect(tokens.value, isNotNull);
    expect(api.authEvent.value, isNull);
  });
  test(
    'Login 401 is an invalid-credentials error, not session expiry',
    () async {
      final tokens = MemoryTokens();
      final api = fakeApi(tokens, (_) => jsonReply({}, 401));
      await expectLater(
        AquarService(api: api).login('person@example.invalid', 'wrong'),
        throwsA(isA<DioException>()),
      );
      expect(api.authEvent.value, isNull);
    },
  );
  testWidgets(
    'Mandatory change cannot pop; confirmation validated; success returns login',
    (tester) async {
      final tokens = MemoryTokens()..value = 'test-session';
      var requests = 0;
      final api = fakeApi(tokens, (_) {
        requests++;
        return jsonReply({});
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ChangePasswordPage(
            requiredChange: true,
            service: AquarService(api: api),
          ),
        ),
      );
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'old-test-value');
      await tester.enterText(fields.at(1), 'new-test-value');
      await tester.enterText(fields.at(2), 'different-value');
      await tester.ensureVisible(find.text('Lưu mật khẩu'));
      await tester.tap(find.text('Lưu mật khẩu'));
      await tester.pump();
      expect(find.text('Xác nhận mật khẩu không khớp.'), findsOneWidget);
      expect(requests, 0);
      await tester.enterText(fields.at(2), 'new-test-value');
      await tester.ensureVisible(find.text('Lưu mật khẩu'));
      await tester.tap(find.text('Lưu mật khẩu'));
      await tester.pumpAndSettle();
      expect(tokens.value, isNull);
      expect(
        find.text('Đã đổi mật khẩu. Vui lòng đăng nhập lại.'),
        findsOneWidget,
      );
      expect(find.text('Đăng nhập'), findsOneWidget);
    },
  );
  testWidgets('Login routes mandatory account directly to password screen', (
    tester,
  ) async {
    final api = fakeApi(
      MemoryTokens(),
      (_) => jsonReply({
        'token': 'test-session',
        'mustChangePassword': true,
        'user': {'id': 1, 'role': 'Employee'},
      }),
    );
    await tester.pumpWidget(AquarApp(api: api));
    await tester.enterText(
      find.byType(TextField).at(0),
      'person@example.invalid',
    );
    await tester.enterText(find.byType(TextField).at(1), 'test-only-password');
    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Đổi mật khẩu'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
