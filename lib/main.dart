// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

// timezone
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// ---------------------------
/// NOTIFICATION SERVICE
/// ---------------------------
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'task_reminders';
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    _channelId,
    'Task Reminders',
    description: 'Thông báo nhắc việc',
    importance: Importance.high,
  );

  Future<void> init() async {
    // Timezone init – đặt mặc định Asia/Ho_Chi_Minh cho chắc trên máy ở VN.
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
    } catch (_) {
      // fallback UTC nếu có gì đó không ổn (hiếm).
    }

    const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: initAndroid);

    await _plugin.initialize(init,
        onDidReceiveNotificationResponse: (resp) {
      // Có thể điều hướng màn hình chi tiết task ở đây nếu muốn (payload chứa taskId).
    });

    // Tạo channel
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Android 13+: Xin quyền hiển thị thông báo
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Xoá tất cả lịch nhắc của 1 task (dựa vào "vùng ID" riêng).
  Future<void> cancelAllForTask(String taskId) async {
    final base = _baseId(taskId);
    // mỗi task mình dành 1000 ID (0..999) — dư sức cho lịch trong 7–14 ngày.
    for (int i = 0; i < 1000; i++) {
      await _plugin.cancel(base * 1000 + i);
    }
  }

  /// Lên lịch cho một mốc giờ cụ thể (one-shot).
  Future<void> scheduleOnce({
    required String taskId,
    required int index,
    required tz.TZDateTime when,
    required String title,
    required String body,
  }) async {
    if (when.isBefore(tz.TZDateTime.now(tz.local))) return;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Task Reminders',
        channelDescription: 'Nhắc việc',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        icon: '@mipmap/ic_launcher',
        styleInformation: const DefaultStyleInformation(true, true),
      ),
    );

    await _plugin.zonedSchedule(
      _baseId(taskId) * 1000 + index,
      title,
      body,
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: taskId,
      androidAllowWhileIdle: true,
    );
  }

  int _baseId(String taskId) =>
      (taskId.hashCode & 0x7fffffff) % 90000 + 10000; // 10_000..99_999
}

/// ---------------------------
/// DATA MODEL
/// ---------------------------
enum TaskStatus { todo, doing, done }

enum RepeatKind {
  none,
  everyXHours, // có khoảng thời gian từ–đến
  dailyAt, // giờ cố định mỗi ngày
}

class RepeatConfig {
  final RepeatKind kind;
  final int intervalHours; // dùng khi everyXHours (>=1)
  final TimeOfDay? from; // dùng khi everyXHours
  final TimeOfDay? to; // dùng khi everyXHours
  final TimeOfDay? dailyTime; // dùng khi dailyAt

  const RepeatConfig.none()
      : kind = RepeatKind.none,
        intervalHours = 0,
        from = null,
        to = null,
        dailyTime = null;

  const RepeatConfig.every({
    required this.intervalHours,
    required this.from,
    required this.to,
  })  : kind = RepeatKind.everyXHours,
        dailyTime = null;

  const RepeatConfig.daily({required this.dailyTime})
      : kind = RepeatKind.dailyAt,
        intervalHours = 0,
        from = null,
        to = null;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'intervalHours': intervalHours,
        'from': _todToMinutes(from),
        'to': _todToMinutes(to),
        'dailyTime': _todToMinutes(dailyTime),
      };

  factory RepeatConfig.fromJson(Map<String, dynamic> json) {
    final kind = RepeatKind.values
        .firstWhere((e) => e.name == json['kind'], orElse: () => RepeatKind.none);
    switch (kind) {
      case RepeatKind.none:
        return const RepeatConfig.none();
      case RepeatKind.dailyAt:
        return RepeatConfig.daily(
          dailyTime: _minutesToTod(json['dailyTime']),
        );
      case RepeatKind.everyXHours:
        return RepeatConfig.every(
          intervalHours: (json['intervalHours'] ?? 1).clamp(1, 24),
          from: _minutesToTod(json['from']),
          to: _minutesToTod(json['to']),
        );
    }
  }

  static int? _todToMinutes(TimeOfDay? t) => t == null ? null : t.hour * 60 + t.minute;
  static TimeOfDay? _minutesToTod(dynamic m) =>
      (m == null) ? null : TimeOfDay(hour: (m ~/ 60), minute: (m % 60));
}

class Task {
  String id;
  String title;
  String detail;
  TaskStatus status;
  DateTime createdAt;
  DateTime? completedAt;

  RepeatConfig repeat;
  int? mutedYyyymmdd; // nếu bằng ngày hôm nay => mute hôm nay

  Task({
    required this.id,
    required this.title,
    required this.detail,
    this.status = TaskStatus.todo,
    DateTime? createdAt,
    this.completedAt,
    this.repeat = const RepeatConfig.none(),
    this.mutedYyyymmdd,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isDone => status == TaskStatus.done;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'detail': detail,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'repeat': repeat.toJson(),
        'mutedYyyymmdd': mutedYyyymmdd,
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'],
        title: json['title'] ?? '',
        detail: json['detail'] ?? '',
        status: TaskStatus.values
            .firstWhere((e) => e.name == json['status'], orElse: () => TaskStatus.todo),
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
        completedAt: json['completedAt'] != null
            ? DateTime.tryParse(json['completedAt'])
            : null,
        repeat: RepeatConfig.fromJson(Map<String, dynamic>.from(json['repeat'] ?? {})),
        mutedYyyymmdd: json['mutedYyyymmdd'],
      );
}

/// ---------------------------
/// STORAGE + STATE
/// ---------------------------
class AppState extends ChangeNotifier {
  static const _storeKey = 'todo_tasks_v2';

  final List<Task> _tasks = [];
  List<Task> get tasks => List.unmodifiable(_tasks);

  String _query = '';
  TaskStatus? _filter; // null = tất cả

  String get query => _query;
  TaskStatus? get filter => _filter;

  set query(String v) {
    _query = v;
    notifyListeners();
  }

  set filter(TaskStatus? s) {
    _filter = s;
    notifyListeners();
  }

  List<Task> get currentTasks => _tasks
      .where((t) =>
          t.status != TaskStatus.done &&
          (_filter == null || t.status == _filter) &&
          (_query.isEmpty ||
              t.title.toLowerCase().contains(_query.toLowerCase()) ||
              t.detail.toLowerCase().contains(_query.toLowerCase())))
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<Task> get historyTasks => _tasks
      .where((t) =>
          t.status == TaskStatus.done &&
          (_query.isEmpty ||
              t.title.toLowerCase().contains(_query.toLowerCase()) ||
              t.detail.toLowerCase().contains(_query.toLowerCase())))
      .toList()
    ..sort((a, b) => (b.completedAt ?? b.createdAt)
        .compareTo(a.completedAt ?? a.createdAt));

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storeKey);
    _tasks.clear();
    if (raw != null && raw.isNotEmpty) {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _tasks.addAll(list.map(Task.fromJson));
    }
    // Sau khi load, tái lên lịch 7 ngày tới cho tất cả
    await _rescheduleAll();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _storeKey, jsonEncode(_tasks.map((e) => e.toJson()).toList()));
  }

  Future<void> addOrUpdate(Task task) async {
    final idx = _tasks.indexWhere((e) => e.id == task.id);
    if (idx >= 0) {
      _tasks[idx] = task;
    } else {
      _tasks.add(task);
    }
    await _save();
    await _rescheduleTask(task);
    notifyListeners();
  }

  Future<void> markDone(Task task, bool done) async {
    final idx = _tasks.indexWhere((e) => e.id == task.id);
    if (idx < 0) return;
    _tasks[idx].status = done ? TaskStatus.done : TaskStatus.todo;
    _tasks[idx].completedAt = done ? DateTime.now() : null;
    await _save();
    await NotificationService.instance.cancelAllForTask(task.id);
    if (!done) {
      await _rescheduleTask(_tasks[idx]);
    }
    notifyListeners();
  }

  Future<void> delete(Task task) async {
    _tasks.removeWhere((e) => e.id == task.id);
    await _save();
    await NotificationService.instance.cancelAllForTask(task.id);
    notifyListeners();
  }

  Future<void> muteToday(Task task) async {
    final idx = _tasks.indexWhere((e) => e.id == task.id);
    if (idx < 0) return;
    _tasks[idx].mutedYyyymmdd = _yyyymmdd(DateTime.now());
    await _save();
    await _rescheduleTask(_tasks[idx]);
    notifyListeners();
  }

  Future<void> _rescheduleAll() async {
    for (final t in _tasks) {
      await _rescheduleTask(t);
    }
  }

  bool _isMutedToday(Task t) =>
      (t.mutedYyyymmdd ?? -1) == _yyyymmdd(DateTime.now());

  Future<void> _rescheduleTask(Task t) async {
    // Huỷ lịch cũ của task này
    await NotificationService.instance.cancelAllForTask(t.id);

    if (t.isDone) return;
    if (t.repeat.kind == RepeatKind.none) return;

    // Nếu mute hôm nay => không tạo lịch cho ngày hiện tại
    final mutedToday = _isMutedToday(t);

    final now = tz.TZDateTime.now(tz.local);
    final startDay = tz.TZDateTime(tz.local, now.year, now.month, now.day);

    // Lên lịch trong 7 ngày tới
    int notifIndex = 0;
    for (int d = 0; d < 7; d++) {
      final day = startDay.add(Duration(days: d));
      final isToday = d == 0;
      if (isToday && mutedToday) continue;

      if (t.repeat.kind == RepeatKind.dailyAt && t.repeat.dailyTime != null) {
        final time = t.repeat.dailyTime!;
        final when = tz.TZDateTime(
            tz.local, day.year, day.month, day.day, time.hour, time.minute);
        await NotificationService.instance.scheduleOnce(
          taskId: t.id,
          index: notifIndex++,
          when: when,
          title: t.title,
          body: t.detail.isEmpty ? 'Đến giờ nhắc việc' : t.detail,
        );
      } else if (t.repeat.kind == RepeatKind.everyXHours &&
          t.repeat.from != null &&
          t.repeat.to != null) {
        final from = t.repeat.from!;
        final to = t.repeat.to!;
        final int step = max(1, t.repeat.intervalHours);

        var cursor = tz.TZDateTime(
            tz.local, day.year, day.month, day.day, from.hour, from.minute);

        final end = tz.TZDateTime(
            tz.local, day.year, day.month, day.day, to.hour, to.minute);

        while (!cursor.isAfter(end)) {
          await NotificationService.instance.scheduleOnce(
            taskId: t.id,
            index: notifIndex++,
            when: cursor,
            title: t.title,
            body: t.detail.isEmpty ? 'Nhắc việc định kỳ' : t.detail,
          );
          cursor = cursor.add(Duration(hours: step));
        }
      }
    }
  }

  static int _yyyymmdd(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
}

/// ---------------------------
/// UI
/// ---------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    final color = const Color(0xFF2F66F4);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ghi chú công việc',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: color,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: color,
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AppState state = AppState();
  int tab = 0;

  @override
  void initState() {
    super.initState();
    state.load();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _TasksPage(state: state),
      _HistoryPage(state: state),
    ];
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Ghi chú công việc'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _SearchBar(
                  hint: tab == 0 ? 'Tìm task...' : 'Tìm trong lịch sử...',
                  initial: state.query,
                  onChanged: (v) => state.query = v,
                ),
              ),
            ),
          ),
          body: pages[tab],
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.task_alt), label: 'Công việc'),
              NavigationDestination(icon: Icon(Icons.history), label: 'Lịch sử'),
            ],
          ),
          floatingActionButton: tab == 0
              ? FloatingActionButton.extended(
                  onPressed: () => _openEdit(context, state, null),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm'),
                )
              : null,
        );
      },
    );
  }

  Future<void> _openEdit(BuildContext context, AppState st, Task? task) async {
    final result = await showModalBottomSheet<Task>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditTaskSheet(initial: task),
    );
    if (result != null) {
      await st.addOrUpdate(result);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu & lên lịch nhắc')),
      );
    }
  }
}

/// ---------------------------
/// Tasks page
/// ---------------------------
class _TasksPage extends StatelessWidget {
  const _TasksPage({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final items = state.currentTasks;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Tất cả'),
                    selected: state.filter == null,
                    onSelected: (_) => state.filter = null,
                  ),
                  FilterChip(
                    label: const Text('Chưa làm'),
                    selected: state.filter == TaskStatus.todo,
                    onSelected: (_) => state.filter = TaskStatus.todo,
                  ),
                  FilterChip(
                    label: const Text('Đang làm'),
                    selected: state.filter == TaskStatus.doing,
                    onSelected: (_) => state.filter = TaskStatus.doing,
                  ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('Chưa có công việc nào'))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final t = items[i];
                        return _TaskTile(task: t, state: state);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.state});
  final Task task;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final subtitle = _repeatLabel(task.repeat);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: ListTile(
        leading: Checkbox(
          value: task.isDone,
          onChanged: (v) => state.markDone(task, v ?? false),
        ),
        title: Text(task.title,
            style: TextStyle(
              decoration: task.isDone ? TextDecoration.lineThrough : null,
            )),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.detail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(task.detail, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(subtitle,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary)),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'edit':
                final result = await showModalBottomSheet<Task>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => _EditTaskSheet(initial: task),
                );
                if (result != null) {
                  await state.addOrUpdate(result);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã lưu & lên lịch nhắc')),
                  );
                }
                break;
              case 'mute':
                await state.muteToday(task);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã tắt thông báo trong hôm nay')),
                );
                break;
              case 'delete':
                await state.delete(task);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã xoá công việc')),
                );
                break;
            }
          },
          itemBuilder: (c) => [
            const PopupMenuItem(value: 'edit', child: Text('Sửa')),
            const PopupMenuItem(value: 'mute', child: Text('Tắt hôm nay')),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Xoá', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  String? _repeatLabel(RepeatConfig r) {
    switch (r.kind) {
      case RepeatKind.none:
        return null;
      case RepeatKind.dailyAt:
        final t = r.dailyTime!;
        return 'Nhắc hằng ngày lúc ${_fmtTime(t)}';
      case RepeatKind.everyXHours:
        final f = r.from!, to = r.to!;
        return 'Mỗi ${r.intervalHours} giờ | ${_fmtTime(f)} → ${_fmtTime(to)}';
    }
  }
}

/// ---------------------------
/// History page
/// ---------------------------
class _HistoryPage extends StatelessWidget {
  const _HistoryPage({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final items = state.historyTasks;
        return items.isEmpty
            ? const Center(child: Text('Chưa có lịch sử'))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: items.length,
                itemBuilder: (c, i) {
                  final t = items[i];
                  return ListTile(
                    leading: const Icon(Icons.check_circle, color: Colors.teal),
                    title: Text(t.title),
                    subtitle: Text(
                        'Hoàn thành: ${_fmtDateTime(t.completedAt ?? t.createdAt)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.restore),
                      tooltip: 'Khôi phục',
                      onPressed: () => state.markDone(t, false),
                    ),
                  );
                },
              );
      },
    );
  }
}

/// ---------------------------
/// Edit Task Bottom Sheet
/// ---------------------------
class _EditTaskSheet extends StatefulWidget {
  const _EditTaskSheet({this.initial});
  final Task? initial;

  @override
  State<_EditTaskSheet> createState() => _EditTaskSheetState();
}

class _EditTaskSheetState extends State<_EditTaskSheet> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _title;
  late TextEditingController _detail;
  TaskStatus _status = TaskStatus.todo;

  RepeatKind _kind = RepeatKind.none;
  int _intervalHours = 2;
  TimeOfDay? _from = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay? _to = const TimeOfDay(hour: 17, minute: 0);
  TimeOfDay? _daily = const TimeOfDay(hour: 9, minute: 0);

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _title = TextEditingController(text: t?.title ?? '');
    _detail = TextEditingController(text: t?.detail ?? '');
    _status = t?.status ?? TaskStatus.todo;
    if (t != null) {
      _kind = t.repeat.kind;
      _intervalHours = t.repeat.intervalHours == 0 ? 2 : t.repeat.intervalHours;
      _from = t.repeat.from ?? _from;
      _to = t.repeat.to ?? _to;
      _daily = t.repeat.dailyTime ?? _daily;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 0.96,
      builder: (context, controller) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Form(
            key: _form,
            child: ListView(
              controller: controller,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                Text(isEdit ? 'Sửa công việc' : 'Thêm công việc',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(
                    labelText: 'Tiêu đề',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Nhập tiêu đề' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _detail,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Chi tiết',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<TaskStatus>(
                  segments: const [
                    ButtonSegment(value: TaskStatus.todo, label: Text('Chưa làm')),
                    ButtonSegment(value: TaskStatus.doing, label: Text('Đang làm')),
                    ButtonSegment(value: TaskStatus.done, label: Text('Đã xong')),
                  ],
                  selected: {_status},
                  onSelectionChanged: (s) => setState(() => _status = s.first),
                ),
                const SizedBox(height: 16),
                Text('Nhắc thông báo',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<RepeatKind>(
                  segments: const [
                    ButtonSegment(value: RepeatKind.none, label: Text('Tắt')),
                    ButtonSegment(value: RepeatKind.everyXHours, label: Text('Mỗi N giờ')),
                    ButtonSegment(value: RepeatKind.dailyAt, label: Text('Giờ cố định')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() => _kind = s.first),
                ),
                const SizedBox(height: 12),
                if (_kind == RepeatKind.everyXHours) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _TimeField(
                          label: 'Từ',
                          value: _from!,
                          onPick: (t) => setState(() => _from = t),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TimeField(
                          label: 'Đến',
                          value: _to!,
                          onPick: (t) => setState(() => _to = t),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Khoảng lặp (giờ): '),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: _intervalHours,
                        items: List.generate(
                                24, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}')))
                            .toList(),
                        onChanged: (v) => setState(() => _intervalHours = v ?? 2),
                      )
                    ],
                  ),
                ],
                if (_kind == RepeatKind.dailyAt) ...[
                  _TimeField(
                    label: 'Giờ cố định',
                    value: _daily!,
                    onPick: (t) => setState(() => _daily = t),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Lưu'),
                  onPressed: _onSave,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onSave() async {
    if (!_form.currentState!.validate()) return;

    RepeatConfig rc;
    switch (_kind) {
      case RepeatKind.none:
        rc = const RepeatConfig.none();
        break;
      case RepeatKind.dailyAt:
        rc = RepeatConfig.daily(dailyTime: _daily);
        break;
      case RepeatKind.everyXHours:
        rc = RepeatConfig.every(
          intervalHours: _intervalHours,
          from: _from,
          to: _to,
        );
        break;
    }

    final now = DateTime.now();
    final task = Task(
      id: widget.initial?.id ?? 't_${now.microsecondsSinceEpoch}',
      title: _title.text.trim(),
      detail: _detail.text.trim(),
      status: _status,
      createdAt: widget.initial?.createdAt ?? now,
      completedAt:
          _status == TaskStatus.done ? (widget.initial?.completedAt ?? now) : null,
      repeat: rc,
      mutedYyyymmdd: widget.initial?.mutedYyyymmdd,
    );

    Navigator.of(context).pop(task);
  }
}

/// ---------------------------
/// WIDGETS HELPER
/// ---------------------------
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.hint, required this.initial, required this.onChanged});
  final String hint;
  final String initial;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: TextEditingController(text: initial),
      onChanged: onChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: hint,
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onPick;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: value,
          helpText: label,
        );
        if (picked != null) onPick(picked);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.schedule),
          const SizedBox(width: 8),
          Text('$label: ${_fmtTime(value)}'),
        ],
      ),
    );
  }
}

/// ---------------------------
/// UTILS
/// ---------------------------
String _fmtTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _fmtDateTime(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
