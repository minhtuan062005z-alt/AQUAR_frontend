import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../models/attendance.dart';
import '../models/user.dart';
import '../services/aquar_service.dart';
import '../services/attendance_location.dart';
import '../widgets/common.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage(
      {super.key, required this.user, this.service, this.locationProvider});
  final AquarUser user;
  final AquarService? service;
  final AttendanceLocationProvider? locationProvider;
  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  late final service = widget.service ?? AquarService();
  late final locationProvider =
      widget.locationProvider ?? GeolocatorAttendanceLocation();
  List<Attendance> rows = [];
  bool loading = true, busy = false, synchronized = false;
  String? loadError, actionError, locationNotice;
  Attendance? lastSuccessfulRecord;
  bool lastWasCheckIn = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Attendance? get current {
    for (final row in rows) {
      if (row.isOpen) return row;
    }
    return rows.isEmpty ? null : rows.first;
  }

  String time(DateTime? value) => value == null
      ? 'Chưa có'
      : DateFormat('dd/MM/yyyy HH:mm:ss').format(value.toLocal());
  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      final result = await service.myAttendance();
      if (result.any((row) => row.staffId != widget.user.id)) {
        throw const FormatException(
            'Máy chủ trả lịch sử không thuộc tài khoản hiện tại.');
      }
      if (mounted) {
        setState(() {
          rows = result;
          synchronized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loadError = errorText(e);
          synchronized = false;
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> refresh() async {
    if (busy || loading) return;
    await load();
  }

  Future<void> submit(bool checkIn) async {
    if (busy || loading || !synchronized) return;
    if (checkIn == (current?.isOpen == true)) return;
    setState(() {
      busy = true;
      actionError = null;
      locationNotice = null;
    });
    try {
      LocationCapture capture;
      try {
        capture = await locationProvider.captureOnce();
      } catch (_) {
        capture = const LocationCapture.unavailable(
            'Không lấy được GPS. Vẫn chấm công, vị trí chưa xác minh.');
      }
      // Do not submit after navigation/logout while a permission dialog was open.
      if (!mounted || service.api.authEvent.value != null) return;
      setState(() => locationNotice = capture.message ??
          'Đã lấy vị trí; Backend xác định trạng thái xác minh.');
      final record = checkIn
          ? await service.checkIn(location: capture.coordinates)
          : await service.checkOut(location: capture.coordinates);
      if (record.staffId != widget.user.id) {
        throw const FormatException('Bản ghi không thuộc tài khoản hiện tại.');
      }
      if (!mounted) return;
      setState(() {
        lastSuccessfulRecord = record;
        lastWasCheckIn = checkIn;
        rows = [record, ...rows.where((a) => a.id != record.id)]
          ..sort((a, b) => b.checkInUtc.compareTo(a.checkInUtc));
      });
      notice(
          context, checkIn ? 'Check-in thành công.' : 'Check-out thành công.');
    } catch (e) {
      if (!mounted) return;
      var message = errorText(e);
      if (e is DioException && e.response?.statusCode == 409) {
        final data = e.response?.data;
        message = data is Map && data['message'] is String
            ? data['message'] as String
            : 'Ca làm vừa thay đổi. Đang tải lại trạng thái.';
      } else if (e is DioException && e.response == null) {
        message =
            'Chưa xác nhận được kết quả ghi công. Đang tải lại trạng thái; không tự gửi lại thao tác.';
      }
      setState(() => actionError = message);
    } finally {
      // POST is never retried automatically. Reconcile using a read, including after conflicts/timeouts.
      if (mounted && service.api.authEvent.value == null) await load();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = current;
    final ready = !busy && !loading && synchronized;
    final state = !synchronized
        ? 'Chưa xác định trạng thái'
        : active == null
            ? 'Chưa Check-in'
            : active.isOpen
                ? 'Đang làm việc'
                : 'Đã Check-out';
    final result = lastSuccessfulRecord;
    final content = RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                  title: 'Chấm công',
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(state,
                            key: const Key('attendance-state'),
                            style: Theme.of(context).textTheme.titleMedium),
                        if (loading)
                          const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: LinearProgressIndicator()),
                        if (active != null) ...[
                          const SizedBox(height: 8),
                          const Text('Ca gần nhất / ca đang mở'),
                          Text('Giờ vào: ${time(active.checkInUtc)}'),
                          Text('Giờ ra: ${time(active.checkOutUtc)}'),
                        ],
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          FilledButton.icon(
                              key: const Key('check-in'),
                              onPressed: ready && active?.isOpen != true
                                  ? () => submit(true)
                                  : null,
                              icon: const Icon(Icons.login),
                              label: const Text('Check-in')),
                          OutlinedButton.icon(
                              key: const Key('check-out'),
                              onPressed: ready && active?.isOpen == true
                                  ? () => submit(false)
                                  : null,
                              icon: const Icon(Icons.logout),
                              label: const Text('Check-out')),
                        ]),
                        if (busy)
                          const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text('Đang xử lý, vui lòng chờ...')),
                        if (actionError != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(actionError!,
                                  style: const TextStyle(color: Colors.red))),
                        if (locationNotice != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(locationNotice!,
                                  key: const Key('location-notice'))),
                        const SizedBox(height: 12),
                        const Text(
                            'Chấm công thông thường bằng tài khoản đăng nhập; không xác thực vân tay hoặc khuôn mặt.'),
                      ])),
              SectionCard(
                  title: 'Lịch sử chấm công cá nhân',
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (loadError != null) ...[
                          Text(loadError!,
                              style: const TextStyle(color: Colors.red)),
                          if (rows.isNotEmpty)
                            const Text(
                                'Đang hiển thị dữ liệu cũ; hãy tải lại để xác nhận trạng thái.'),
                          TextButton(
                              onPressed: busy || loading ? null : refresh,
                              child: const Text('Thử lại')),
                        ],
                        if (loading && rows.isEmpty)
                          const Text('Đang tải lịch sử...'),
                        if (!loading && loadError == null && rows.isEmpty)
                          const Text('Chưa có lịch sử chấm công.'),
                        for (final row in rows)
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(row.isOpen
                                  ? Icons.timelapse
                                  : Icons.check_circle_outline),
                              title: Text(
                                  'Ngày ${DateFormat('dd/MM/yyyy').format(row.checkInUtc.toLocal())} • ${row.isOpen ? 'Đang làm việc' : 'Đã Check-out'}'),
                              subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        'Vào: ${time(row.checkInUtc)}\nRa: ${time(row.checkOutUtc)}\n${row.manual ? 'Quản lý ghi nhận thủ công' : row.method == 'manual' ? 'Chấm công thông thường' : 'Phương thức: ${row.method}'}'),
                                    const SizedBox(height: 6),
                                    _LocationDetails(
                                        label: 'Vị trí Check-in',
                                        location: row.checkInLocation),
                                    if (row.checkOutUtc != null)
                                      _LocationDetails(
                                          label: 'Vị trí Check-out',
                                          location: row.checkOutLocation),
                                  ])),
                        if (rows.isNotEmpty)
                          const Text(
                              'Tối đa 200 bản ghi gần nhất theo API hiện tại. Kéo xuống để tải lại.'),
                      ])),
            ]));
    return LayoutBuilder(
        builder: (context, constraints) => Column(children: [
              if (result != null)
                ConstrainedBox(
                    constraints:
                        BoxConstraints(maxHeight: constraints.maxHeight * 0.45),
                    child: SingleChildScrollView(
                      child: Card(
                          key: const Key('attendance-result'),
                          color:
                              Theme.of(context).colorScheme.secondaryContainer,
                          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: SizedBox(
                            width: double.infinity,
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                          'Lần chấm công thành công gần nhất'),
                                      if (actionError != null)
                                        Text(
                                            'Lần thử mới nhất có lỗi; đây là kết quả thành công trước đó.',
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error)),
                                      Text(
                                          lastWasCheckIn
                                              ? 'Check-in thành công.'
                                              : 'Check-out thành công.',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      Text(
                                          'Thời gian Backend: ${time(lastWasCheckIn ? result.checkInUtc : result.checkOutUtc)}',
                                          key: const Key('result-time')),
                                      _LocationDetails(
                                          location: lastWasCheckIn
                                              ? result.checkInLocation
                                              : result.checkOutLocation),
                                    ])),
                          )),
                    )),
              Expanded(child: content),
            ]));
  }
}

class _LocationDetails extends StatelessWidget {
  const _LocationDetails({this.label, this.location});
  final String? label;
  final AttendanceLocationInfo? location;
  @override
  Widget build(BuildContext context) {
    final value = location;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (label != null)
        Text(label!, style: const TextStyle(fontWeight: FontWeight.w600)),
      Text(value?.statusLabel ?? 'Chưa xác minh vị trí',
          style: TextStyle(
              color: value?.isOutside == true
                  ? Theme.of(context).colorScheme.error
                  : null,
              fontWeight: FontWeight.w600)),
      Text(value?.hasCoordinates == true
          ? 'GPS: ${value!.latitude!.toStringAsFixed(6)}, ${value.longitude!.toStringAsFixed(6)}'
          : 'GPS: Chưa có tọa độ từ Backend'),
      if (value?.displayedDistance != null)
        Text(
            'Khoảng cách đến công ty: ${value!.displayedDistance!.toStringAsFixed(1)} m'),
    ]);
  }
}
