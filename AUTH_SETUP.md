# Đăng nhập và đổi mật khẩu AQUAR

Giữ bố cục Material 3 và cấu trúc màn hình hiện có. Đăng nhập lưu JWT bằng flutter_secure_storage, chuẩn hóa vai trò Admin/Manager/Employee. Admin/Manager giữ tab Nhân viên; Employee chỉ có các tab sẵn có dành cho mình. Quyền API vẫn do Backend quyết định.

Nếu mustChangePassword=true (ở response hoặc user), ứng dụng thay màn hình đăng nhập bằng màn hình đổi mật khẩu bắt buộc, không cho quay lại màn hình nghiệp vụ. API trả 403 với code MUST_CHANGE_PASSWORD cũng kích hoạt luồng này. Mọi vai trò có thể tự đổi mật khẩu qua biểu tượng Cài đặt tài khoản trên trang chủ.

PUT /api/account/password gửi currentPassword, newPassword, confirmNewPassword. Mật khẩu mới cần ít nhất 12 ký tự và tối đa 72 byte UTF-8. Thành công xóa JWT cũ, xóa các route cũ và yêu cầu đăng nhập lại. Sai mật khẩu hiện tại/validation giữ màn hình cho người dùng sửa. Không lưu mật khẩu vào thiết bị hoặc ghi log request/token.

401 trên API có JWT xóa phiên và chuyển về đăng nhập. 401 từ login hiển thị lỗi email/mật khẩu. 403 thông thường hiển thị thiếu quyền, không xóa phiên. Có thông báo lỗi mạng và giới hạn đăng nhập 429. Đăng xuất gọi API và luôn xóa token cục bộ khi máy chủ không truy cập được; nếu mất mạng, không thể xác nhận việc thu hồi token phía máy chủ.

## Kết nối và chạy

Backend phải đang chạy và migration RequirePasswordChange phải được áp dụng trước khi kiểm thử luồng mới. Đợt Flutter này không sửa Backend/SQL/migration và không xác nhận migration đã được áp dụng.

SDK được tìm thấy tại D:\LTDD\flutter\flutter nhưng chưa có trong PATH. Mở PowerShell ngoài sandbox có quyền ghi Flutter cache và Pub cache:

```powershell
cd D:\LTDD_FINAL\AQUAR_Flutter_Complete\aquar_app
& 'D:\LTDD\flutter\flutter\bin\flutter.bat' pub get
& 'D:\LTDD\flutter\flutter\bin\flutter.bat' analyze
& 'D:\LTDD\flutter\flutter\bin\flutter.bat' test
```

- Android Emulator: mặc định http://10.0.2.2:5080 trỏ về máy chạy emulator.
- Desktop: mặc định http://127.0.0.1:5080.
- Điện thoại thật: dùng địa chỉ LAN của máy Backend qua --dart-define=API_BASE_URL=http://IP_MAY_BACKEND:5080. Máy chủ phải lắng nghe địa chỉ LAN và firewall cho phép kết nối.
- Không thêm /api vào API_BASE_URL. Không tắt xác minh chứng chỉ TLS trong Dio.

Hiện thư mục này chỉ có lib/test và pubspec, chưa có Android scaffold. Chưa chạy Android thực tế. Để tạo platform trong một bước thiết lập riêng, chạy `flutter create --platforms=android .`; kiểm tra manifest có quyền INTERNET. Nếu dùng HTTP phát triển, Android cần cấu hình cleartext phù hợp cho môi trường phát triển; khi triển khai dùng HTTPS với chứng chỉ được thiết bị tin cậy. Web còn phụ thuộc cấu hình CORS của Backend, chưa được kiểm thử trong đợt này.

Sau khi có Android scaffold và emulator:

```powershell
& 'D:\LTDD\flutter\flutter\bin\flutter.bat' run --dart-define=API_BASE_URL=http://10.0.2.2:5080
```

Không nhập mật khẩu/JWT vào --dart-define hoặc source.

## Trạng thái xác minh đợt này

- Đã thêm test/auth_test.dart: parsing vai trò, cờ bắt buộc đổi, payload ba trường, token bị xóa khi đổi thành công, lỗi 401/403, validation xác nhận và điều hướng đăng nhập → đổi mật khẩu → đăng nhập lại.
- Đã thử flutter pub get/analyze/test nhưng wrapper không vượt qua bước lấy khóa cache SDK ngoài workspace; đã dừng các lệnh do chính đợt này khởi chạy để không để lại terminal treo. shared.bat che stderr ở bước lấy flutter.bat.lock.
- Dart CLI ban đầu báo PathAccessException khi ghi C:\Users\Tuan\AppData\Roaming\.dart-tool\dart-flutter-telemetry.log (Access is denied). Với --suppress-analytics, kiểm tra parse bằng dart format --output=none lib test đã chạy thành công; còn cảnh báo chưa resolve flutter_lints vì pub get chưa hoàn tất.
- Chưa có kết quả flutter analyze hoặc flutter test thành công. Không xem việc parse thành công là thay thế analyze/test.
- Sửa dấu ngoặc thiếu trong LoginPage và thêm đúng một dấu chấm phẩy thiếu có sẵn trong attendance_page.dart để parser có thể đọc toàn bộ ứng dụng; không thay đổi nghiệp vụ chấm công/báo cáo.

Kiểm tra thủ công sau khi chạy: đăng nhập sai; đăng nhập từng vai trò; tài khoản tạm không vào Home; xác nhận mật khẩu không khớp; đổi mật khẩu thành công và đăng nhập bằng mật khẩu mới; reset mật khẩu từ Backend rồi dùng token cũ phải về Login; ngắt mạng hiển thị lỗi và nút cho phép thử lại.
