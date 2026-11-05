import 'dart:async';
import 'package:local_auth/local_auth.dart';

class BiometricCapability {
  const BiometricCapability(this.available, this.message);
  final bool available;
  final String message;
}

abstract class AttendanceBiometrics {
  Future<BiometricCapability> capability();
  Future<bool> authenticate();
  Future<void> cancel();
}

class SystemAttendanceBiometrics implements AttendanceBiometrics {
  SystemAttendanceBiometrics({LocalAuthentication? auth})
      : auth = auth ?? LocalAuthentication();
  final LocalAuthentication auth;
  @override
  Future<BiometricCapability> capability() async {
    try {
      if (!await auth.isDeviceSupported() || !await auth.canCheckBiometrics) {
        return const BiometricCapability(
            false, 'Thiết bị không hỗ trợ sinh trắc học hệ thống.');
      }
      final types = await auth.getAvailableBiometrics();
      if (types.isEmpty) {
        return const BiometricCapability(
            false, 'Chưa đăng ký sinh trắc học trong Cài đặt Android.');
      }
      // Android may expose only strong/weak categories, not the actual modality.
      final face = types.contains(BiometricType.face);
      final fingerprint = types.contains(BiometricType.fingerprint);
      return BiometricCapability(
          true,
          face
              ? 'Hệ thống báo có khuôn mặt đã đăng ký. Android chọn phương thức xác thực.'
              : fingerprint
                  ? 'Có vân tay đã đăng ký. Chưa xác nhận hỗ trợ khuôn mặt qua BiometricPrompt.'
                  : 'Có sinh trắc học đã đăng ký. Android không cung cấp loại cụ thể; chưa xác nhận hỗ trợ khuôn mặt.');
    } catch (_) {
      return const BiometricCapability(
          false, 'Không kiểm tra được sinh trắc học trên thiết bị này.');
    }
  }

  @override
  Future<bool> authenticate() async {
    try {
      if (!(await capability()).available) return false;
      return await auth
          .authenticate(
              localizedReason: 'Xác thực sinh trắc học để chấm công AQUAR',
              options: const AuthenticationOptions(
                  biometricOnly: true,
                  stickyAuth: false,
                  useErrorDialogs: false))
          .timeout(const Duration(seconds: 45), onTimeout: () async {
        await auth.stopAuthentication();
        return false;
      });
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await auth.stopAuthentication();
    } catch (_) {/* No request is sent. */}
  }
}
