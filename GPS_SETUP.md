# GPS một lần khi chấm công

Đợt này chỉ sửa Flutter, test và Android manifest; không kết nối hoặc thay đổi Backend, SQL Server, migration hay Render.

## Luồng hoạt động

Khi bấm Check-in/Check-out, khóa nút ngay, kiểm tra location service và quyền; chỉ xin quyền nếu đang denied. deniedForever không tiếp tục hỏi. Chỉ nhận quyền whileInUse/always đã được hệ điều hành cấp, không yêu cầu quyền nền. Dùng geolocator 14.1.2, getCurrentPosition với LocationSettings, accuracy high và timeLimit 10 giây. Có giới hạn 20 giây cho toàn bộ bước service/quyền/GPS; nếu người dùng phản hồi dialog muộn sau timeout, không khởi động việc lấy GPS tiếp theo cho thao tác đã hết hạn.

Không dùng getPositionStream, getLastKnownPosition hoặc theo dõi liên tục. Không cache tọa độ cho lần chấm công sau, không hardcode tọa độ trong app, không log tọa độ/JWT/mật khẩu. Mỗi lần bấm lấy một fix mới. Các tọa độ tổng hợp trong test chỉ là fixture, không được đưa vào app/database.

Nếu GPS tắt, quyền bị từ chối/vĩnh viễn, lỗi plugin/thiết bị hoặc timeout: vẫn gửi POST một lần không có tọa độ; màn hình hiển thị vị trí chưa xác minh. Không tự mở Settings hoặc buộc người dùng bật GPS. Nếu rời trang/đăng xuất trong khi chờ quyền, không gửi POST từ trang đã bị đóng. Dialog hệ điều hành có thể còn mở dù timeout của app đã hết; app không tự đóng dialog đó.

Giữ nguyên JWT, role, bắt buộc đổi mật khẩu, xử lý 401/403, chống gửi trùng và tải lại lịch sử sau POST/lỗi. Không tự retry POST. Không xác định bán kính công ty hoặc tuyên bố GPS được xác minh ở client; việc xét phạm vi thuộc Backend.

## Payload

POST /api/attendance/check-in và POST /api/attendance/check-out:

- Có GPS: method="manual", latitude và longitude là hai số lấy từ getCurrentPosition.
- Không GPS: chỉ {"method":"manual"}, bỏ hẳn hai trường tọa độ.
- Không gửi giờ thiết bị hoặc tự tính trạng thái xác minh. Backend lấy giờ server, xử lý thiếu cấu hình công ty và cảnh báo phạm vi.

Service nhận GpsCoordinates tùy chọn để giữ tương thích các caller cũ. Tọa độ không hữu hạn/sai phạm vi không được đưa vào request. Model Attendance hiện giữ cách đọc lịch sử cũ; không bổ sung giao diện cảnh báo Admin trong đợt này.

## Phiên bản và Android

Flutter hiện được ghi nhận 3.47.5 / Dart 3.13.4; geolocator 14.1.2 yêu cầu Dart >=3.5 nên pubspec đã điều chỉnh giới hạn tối thiểu. Tài liệu chính thức: https://pub.dev/packages/geolocator/versions/14.1.2 và source package cache đã đối chiếu. Android cần AndroidX và compileSdk ít nhất 35 theo tài liệu package; cần kiểm tra trên scaffold/SDK thực tế.

Ban đầu repo không có thư mục Android. Đã chuẩn bị main AndroidManifest theo template SDK Flutter với INTERNET, ACCESS_FINE_LOCATION và ACCESS_COARSE_LOCATION; không ACCESS_BACKGROUND_LOCATION, không background service hoặc yêu cầu quyền location nền. Debug manifest chỉ bật HTTP cleartext để thử Backend local. Release không bật cleartext; dùng HTTPS được thiết bị tin cậy.

Chưa có Gradle, MainActivity và tài nguyên Android đầy đủ trong repo hiện tại. Manifest không thay thế scaffold hoàn chỉnh. Trên PowerShell có quyền Flutter SDK, tạo phần còn thiếu bằng flutter create --platforms=android . (không dùng --overwrite), sau đó kiểm tra manifest giữ đủ quyền và Gradle compileSdk đáp ứng package. Lệnh không được chạy tự động trong lượt này vì SDK bị chặn.

## Kiểm thử đã viết và kết quả thực tế

Thêm test/attendance_gps_test.dart với 18 trường hợp: lấy GPS một lần, xin quyền/grant, denied/deniedForever, service tắt, timeout, kết quả quyền đến muộn, lỗi thiết bị, payload tọa độ cho hai POST và widget Check-in/out vẫn thành công ở cả trường hợp có GPS, denied, tắt GPS, timeout. Adapter LocationDevice được giả lập, không gọi cảm biến/test database thật.

test/attendance_test.dart được cập nhật signature và provider không GPS để giữ các test cũ độc lập khỏi native plugin. Các test cũ vẫn kiểm tra payload không có tọa độ. Tổng số dự kiến 50 sau khi thêm 18 vào 32 trước đó; chưa có kết quả PASS cho source mới.

Đã thử flutter pub get/analyze/test bằng SDK D:\LTDD\flutter\flutter: wrapper không qua bước khởi động/khóa cache ngoài workspace, không có output; đã dừng các phiên tự khởi chạy. Dart analyze thất bại trước phân tích với CreateFile failed 5 / Access is denied khi khởi chạy analysis_server_aot. Không vô hiệu test hoặc thay cache SDK để vượt sandbox.

Đã chạy Dart format kiểm tra parse toàn bộ lib/test thành công; đã parse XML hai manifest và xác nhận không có quyền background location. Đây không thay thế analyze/test/native Android. pubspec.lock và package_config cần được công cụ pub get cập nhật sau khi chạy được SDK; không sửa thủ công file dependency được sinh tự động.

## Lệnh chạy trên PowerShell

```powershell
cd D:\LTDD_FINAL\AQUAR_Flutter_Complete\aquar_app
$flutterCmd = 'D:\LTDD\flutter\flutter\bin\flutter.bat'
& $flutterCmd pub get
& $flutterCmd analyze
& $flutterCmd test
& $flutterCmd test test/attendance_gps_test.dart
# Chỉ cần khi Android scaffold còn thiếu; không dùng --overwrite.
& $flutterCmd create --platforms=android .
& $flutterCmd run --dart-define=API_BASE_URL=http://10.0.2.2:5080
```

Android Emulator dùng 10.0.2.2 để về Backend PC. Điện thoại thật dùng IP LAN của PC, Backend lắng nghe LAN và firewall phù hợp; không mở SQL Server ra Internet. Backend/migration GPS đã sẵn sàng theo trạng thái người dùng cung cấp, chưa được kiểm tra lại từ Flutter.

## Checklist Android thật

1. Dùng tài khoản/môi trường được phép vì bấm ghi công sẽ tạo dữ liệu thật nếu trỏ AQUAR_DB thật.
2. Bật định vị, cấp quyền khi dùng ứng dụng: mỗi nút gửi tọa độ, giờ vẫn do server lấy. Kiểm tra cả quyền approximate/precise; approximate có thể có sai số lớn và ảnh hưởng cảnh báo khoảng cách.
3. Từ chối quyền, chọn không hỏi lại hoặc tắt định vị: chấm công vẫn thành công và thông báo chưa xác minh.
4. Khi GPS không có fix trong thời hạn, app vẫn gửi không tọa độ; dialog quyền phản hồi muộn không được kích hoạt ghi công lần hai.
5. Nhấn liên tục, chuyển trang/đăng xuất khi chờ quyền, mất mạng, 401/403 và bắt buộc đổi mật khẩu: không ghi trùng/không bỏ qua luồng xác thực.
6. Kiểm tra manifest merge không có background location; kiểm tra release dùng HTTPS. Chưa chạy Android thật hoặc kiểm tra mức tiêu thụ pin trong lượt này.
