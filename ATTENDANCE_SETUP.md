# Chấm công cá nhân — Flutter

GPS tùy chọn đã được bổ sung trong lượt mới: xem GPS_SETUP.md. Luồng hiện tại lấy vị trí một lần trước khi gửi manual; khi không lấy được vẫn gửi request không có tọa độ. Các kết quả kiểm thử cũ bên dưới là lịch sử trước thay đổi GPS, không thay thế việc chạy lại test mới.

## Sửa kiểm thử SnackBar (lượt tiếp theo)

Người dùng báo kết quả trước sửa: 30 PASS, 1 FAIL ở Check-in/out update server state and history, không tìm thấy Check-in thành công.

Nguyên nhân trong code test: showPage đặt AttendancePage trực tiếp làm home của MaterialApp, thiếu Scaffold. Trong ứng dụng thật, AttendancePage là body của Scaffold trong HomePage. ScaffoldMessenger.showSnackBar yêu cầu có Scaffold con; Flutter SDK scaffold.dart có assertion "ScaffoldMessenger.showSnackBar was called, but there are currently no descendant Scaffolds to present to." Assertion xảy ra sau khi POST thành công, bị catch trong submit bắt và chuyển thành actionError; cuối cùng vẫn tải lại lịch sử nhưng không có SnackBar. Không phải bằng chứng POST thất bại hoặc chỉ cần đợi thêm pump.

Đã sửa harness chung và harness của test loading thành MaterialApp → Scaffold → AttendancePage. Giữ assertion Check-in thành công; kiểm tra thêm trạng thái đang làm, dữ liệu giờ ra còn trống và số GET sau ghi công. Sau khi xác nhận SnackBar Check-in, test hideCurrentSnackBar rồi pumpAndSettle để xóa thông báo cũ khỏi hàng đợi, sau đó Check-out và xác nhận thông báo, trạng thái, lịch sử/giờ ra và GET tiếp theo. Không xóa/skip test hoặc giảm assertion. Không thay đổi POST/GET hay cơ chế cập nhật trạng thái ứng dụng.

Đã thêm braces cho các if nhiều dòng trong api.dart, attendance.dart, attendance_page.dart, change_password_page.dart và common.dart, chỉ thay cú pháp khối, không thay logic.

Xác minh trong phiên này: dart --suppress-analytics format --output=none lib test exit code 0, không lỗi parse. Đã thử test riêng, full flutter test và flutter analyze; wrapper không qua bước khởi động và đã được hủy để không để terminal treo. Dart analyze không khởi chạy được analysis_server_aot do CreateFile failed 5 / Access is denied. Chưa có số PASS/FAIL hoặc số info mới, không khẳng định 31/31 PASS.

Chạy lại trên PowerShell có quyền SDK:

```powershell
cd D:\LTDD_FINAL\AQUAR_Flutter_Complete\aquar_app
$flutterCmd = 'D:\LTDD\flutter\flutter\bin\flutter.bat'
& $flutterCmd test test/attendance_test.dart --plain-name 'Check-in/out update server state and history'
& $flutterCmd test
& $flutterCmd analyze
```

## Hợp đồng Backend đã đối chiếu

Nguồn đọc: AQUAR.Api/Controllers/AttendanceController.cs, DTOs/Requests.cs. Không sửa Backend/database/migration trong đợt này.

| API | Request | Response thành công |
|---|---|---|
| POST /api/attendance/check-in | {"method":"manual"} | HTTP 200, bản ghi chấm công |
| POST /api/attendance/check-out | {"method":"manual"} | HTTP 200, bản ghi chấm công đã có giờ ra |
| GET /api/attendance/history | Không có staffId: Backend tự lấy user từ JWT | HTTP 200, tối đa 200 bản ghi gần nhất |

Bản ghi gồm id, staffId, checkInUtc, checkOutUtc (có thể null), method, manual, recordedBy, reason. Flutter chỉ đọc các trường cần hiển thị; không gửi staffId hoặc giờ thiết bị để tự ghi công. Backend quyết định giờ vào/ra. API yêu cầu JWT và cho phép lấy lịch sử bản thân cho cả ba vai trò. API manual dành cho Admin/Manager không được dùng làm đường vòng cho Employee.

Đã chuẩn hóa phương thức: Flutter gửi manual cho chấm công thông thường, không gọi local_auth, vân tay, khuôn mặt, NFC hoặc GPS. Backend mới nhận manual và giữ biometric cho client/bản ghi cũ; không coi nhãn biometric là bằng chứng thiết bị. Cần chạy Backend đã cập nhật trước khi thử Flutter mới, vì Backend cũ sẽ trả 400 cho manual. method=manual với manual=false là tự ghi công; manual=true vẫn dành cho quản lý nhập hộ. Không sửa bản ghi cũ hoặc schema.

## Hành vi

- Lấy lịch sử từ Backend khi mở tab, khi kéo tải lại và sau thao tác ghi công. Không có dữ liệu mẫu trong ứng dụng; fixture chỉ có trong file test.
- Rỗng: Chưa Check-in; ca có checkOutUtc=null: Đang làm việc; không có ca mở nhưng có lịch sử: Đã Check-out của ca gần nhất. Không tự áp quy tắc một ca/ngày; có thể mở ca mới sau khi kết thúc ca cũ nếu Backend cho phép.
- Hiển thị giờ vào/ra và ngày theo múi giờ thiết bị. Các trường tên UTC được đọc là UTC ngay cả khi SQL datetime2 trả ISO không có Z.
- Khóa nút khi đang tải/chưa biết trạng thái/đang gửi, chống nhấn liên tục. Không tự retry POST.
- Sau lỗi 400/409 hoặc timeout, dùng GET tải lại để xác nhận trạng thái thực tế. Nếu Backend đã ghi dù response bị mất, trạng thái tải lại sẽ khóa Check-in và mở Check-out. Nếu không đồng bộ lại được, khóa cả hai nút và cho phép thử tải lại.
- Có loading, danh sách rỗng, dữ liệu cũ kèm cảnh báo, lỗi/thử lại, thông báo thành công. JWT/401/403/MUST_CHANGE_PASSWORD tiếp tục dùng interceptor và điều hướng xác thực hiện có.

## Kiểm thử đã chuẩn bị

test/attendance_test.dart hiện có 15 trường hợp: parse UTC/checkout/dữ liệu sai, HTTP method=manual/request/JWT hai endpoint, giữ ý nghĩa lịch sử biometric và ca quản lý nhập hộ, lịch sử cá nhân, 401/403, trạng thái rỗng, luồng vào/ra, chống gửi trùng, loading, lỗi lịch sử/thử lại, 409 và timeout với server đã ghi công. Người dùng đã xác nhận 31/31 PASS và analyze không vấn đề trước thay đổi manual; lượt mới chưa chạy thành công Flutter SDK trong sandbox, không xác nhận 32/32 PASS. Backend build và 89 checks đã đạt; chi tiết ở AQUAR.Api/ATTENDANCE_METHODS.md.

Đợt này đã thử flutter pub get, flutter analyze, flutter test bằng SDK D:\LTDD\flutter\flutter. Wrapper dừng ở bước khởi động/khóa cache và không có output; đã hủy các phiên do đợt này khởi chạy. Dart analyze cũng thất bại trước khi phân tích:

```text
CreateFile failed 5 (Access is denied.)
ProcessException: Access is denied (at ../../runtime/bin/process_win.cc:744)
Command: ...dartaotruntime.exe ...analysis_server_aot.dart.snapshot ...
```

Đã chạy dart --suppress-analytics format --output=none lib test thành công, không lỗi parse. Đây không thay thế type checking, flutter analyze hoặc flutter test. Chưa xác nhận 14 test mới PASS; kết quả 17 test trước đây do người dùng cung cấp không được coi là kết quả cho source mới. Chưa thử ghi dữ liệu SQL thật hoặc chạy Android thực tế.

## Chạy lại kiểm thử trên máy có quyền SDK

```powershell
cd D:\LTDD_FINAL\AQUAR_Flutter_Complete\aquar_app
$flutterCmd = 'D:\LTDD\flutter\flutter\bin\flutter.bat'
& $flutterCmd pub get
& $flutterCmd analyze
& $flutterCmd test
& $flutterCmd test test/attendance_test.dart
```

## Kiểm tra trên Android

1. Chạy Backend local và xác minh database/schema hiện có sẵn sàng; đợt Flutter này không tạo database hoặc chạy migration. Dùng tài khoản Employee kiểm thử do bạn quản lý, đã đổi mật khẩu tạm. Các thao tác Check-in/Check-out bên dưới sẽ ghi dữ liệu thật nếu trỏ database thật: chỉ chủ động thực hiện trên tài khoản/môi trường được phép.
2. Nếu dự án chưa có Android scaffold, chuẩn bị scaffold ở bước thiết lập Android riêng theo AUTH_SETUP.md; kiểm tra quyền INTERNET và cấu hình HTTP phát triển. Không tắt kiểm tra chứng chỉ TLS của Dio.
3. Android Emulator cùng máy Backend:

```powershell
& $flutterCmd run --dart-define=API_BASE_URL=http://10.0.2.2:5080
```

Điện thoại thật: dùng địa chỉ LAN của máy Backend và cổng đang lắng nghe; cần mạng/firewall phù hợp. Không dùng 127.0.0.1 trên điện thoại để trỏ về PC. Không mở SQL Server ra Internet.

4. Đăng nhập Employee, mở tab Chấm công: kiểm tra trạng thái và lịch sử lấy từ API. Nhấn Check-in một lần: thấy thông báo thành công, giờ vào và trạng thái đang làm; Check-in bị khóa, Check-out được bật. Nhấn nhiều lần nhanh không được tạo nhiều POST đồng thời.
5. Nhấn Check-out: thấy giờ ra, trạng thái đã kết thúc, lịch sử cập nhật. Đóng/mở lại tab hoặc kéo tải lại: dữ liệu vẫn lấy từ Backend, không mất vì chỉ lưu trong RAM.
6. Ngắt mạng: phải thấy lỗi, không tự gửi lặp. Kết nối lại rồi tải lại trước khi quyết định thao tác tiếp. Kiểm tra 401 khi token bị thu hồi chuyển về đăng nhập, và tài khoản bắt buộc đổi mật khẩu được đưa về màn hình tương ứng.

Giới hạn còn lại: không có phân trang/lọc ngày vì API hiện giới hạn 200 bản ghi; chưa có idempotency key phía Backend nên Flutter chỉ ngăn gửi đồng thời và đối chiếu bằng GET sau lỗi. Không thêm quy tắc đi muộn, OT hoặc tính lương.
