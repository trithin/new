import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
  await NotificationService.instance.init();
  runApp(const MyApp());
}

enum TaskStatus { todo, doing, done }
enum TaskPriority { low, normal, high }
enum RepeatFreq { none, daily, workdays, weekly }

String statusLabel(TaskStatus s) => switch (s) {
      TaskStatus.todo => 'Chưa làm',
      TaskStatus.doing => 'Đang làm',
      TaskStatus.done => 'Đã xong',
    };
String priorityLabel(TaskPriority p) => switch (p) {
      TaskPriority.low => 'Thấp',
      TaskPriority.normal => 'Thường',
      TaskPriority.high => 'Cao',
    };
Color priorityColor(TaskPriority p) => switch (p) {
      TaskPriority.low => Colors.blueGrey,
      TaskPriority.normal => Colors.teal,
      TaskPriority.high => Colors.deepOrange,
    };

TaskPriority priorityFromString(String? s) {
  switch (s) {
    case 'low':
    case 'Thấp':
      return TaskPriority.low;
    case 'high':
    case 'Cao':
      return TaskPriority.high;
    default:
      return TaskPriority.normal;
  }
}

TaskStatus statusFromString(String? s) {
  switch (s) {
    case 'todo':
    case 'Chưa làm':
      return TaskStatus.todo;
    case 'doing':
    case 'Đang làm':
      return TaskStatus.doing;
    case 'done':
    case 'Đã xong':
      return TaskStatus.done;
    default:
      return TaskStatus.todo;
  }
}

class StatusEvent {
  final TaskStatus status;
  final DateTime at;
  StatusEvent(this.status, this.at);
  Map<String, dynamic> toJson() => {'status': status.name, 'at': at.toIso8601String()};
  factory StatusEvent.fromJson(Map<String, dynamic> j) =>
      StatusEvent(statusFromString(j['status']), DateTime.parse(j['at']));
}

class TaskItem {
  final String id;
  String title;
  String details;
  TaskStatus status;
  DateTime createdAt;
  DateTime? completedAt;
  DateTime? muteForDate;
  DateTime? dueDate;
  TaskPriority priority;
  List<String> tags;
  DateTime? snoozeUntil;
  RepeatFreq repeat;
  List<StatusEvent> history;

  TaskItem({
    required this.id,
    required this.title,
    required this.details,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.muteForDate,
    this.dueDate,
    this.priority = TaskPriority.normal,
    List<String>? tags,
    this.snoozeUntil,
    this.repeat = RepeatFreq.none,
    List<StatusEvent>? history,
  })  : tags = tags ?? [],
        history = history ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'details': details,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'muteForDate': _dateOnlyIso(muteForDate),
        'dueDate': dueDate?.toIso8601String(),
        'priority': priority.name,
        'tags': tags,
        'snoozeUntil': snoozeUntil?.toIso8601String(),
        'repeat': repeat.name,
        'history': history.map((e) => e.toJson()).toList(),
      };

  factory TaskItem.fromJson(Map<String, dynamic> j) => TaskItem(
        id: j['id'],
        title: j['title'] ?? '',
        details: j['details'] ?? '',
        status: statusFromString(j['status']),
        createdAt: DateTime.parse(j['createdAt']),
        completedAt: j['completedAt'] == null ? null : DateTime.parse(j['completedAt']),
        muteForDate: j['muteForDate'] == null ? null : DateTime.parse(j['muteForDate']),
        dueDate: j['dueDate'] == null ? null : DateTime.parse(j['dueDate']),
        priority: priorityFromString(j['priority']),
        tags: ((j['tags'] ?? []) as List).map((e) => '$e').toList(),
        snoozeUntil: j['snoozeUntil'] == null ? null : DateTime.parse(j['snoozeUntil']),
        repeat: _repeatFromString(j['repeat']),
        history: ((j['history'] ?? []) as List).map((e) => StatusEvent.fromJson(e)).toList(),
      );
}

String? _dateOnlyIso(DateTime? d) => d == null
    ? null
    : DateTime(d.year, d.month, d.day).toIso8601String();
RepeatFreq _repeatFromString(String? s) {
  switch (s) {
    case 'daily':
      return RepeatFreq.daily;
    case 'workdays':
      return RepeatFreq.workdays;
    case 'weekly':
      return RepeatFreq.weekly;
    default:
      return RepeatFreq.none;
  }
}

class TaskStore {
  static const _k = 'tasks_v2';
  static final TaskStore instance = TaskStore._();
  TaskStore._();

  Future<List<TaskItem>> load() async {
    final sp = await SharedPreferences.getInstance();
    final txt = sp.getString(_k);
    if (txt == null || txt.isEmpty) return [];
    return (jsonDecode(txt) as List).map((e) => TaskItem.fromJson(e)).toList();
  }

  Future<void> save(List<TaskItem> tasks) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_k, jsonEncode(tasks.map((e) => e.toJson()).toList()));
  }
}

// =================== Notifications ===================
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final fln.FlutterLocalNotificationsPlugin _plugin = fln.FlutterLocalNotificationsPlugin();

  static const _tasksChannel = fln.AndroidNotificationDetails(
    'tasks_channel',
    'Nhắc công việc',
    channelDescription: 'Nhắc việc chưa hoàn thành 9h-17h và snooze',
    importance: fln.Importance.high,
    priority: fln.Priority.high,
  );
  static const _digestChannel = fln.AndroidNotificationDetails(
    'digest_channel',
    'Tổng kết hằng ngày',
    channelDescription: 'Tổng kết công việc chưa xong lúc 9h',
    importance: fln.Importance.defaultImportance,
    priority: fln.Priority.defaultPriority,
  );

  Future<void> init() async {
    if (kIsWeb) return;
    const fln.AndroidInitializationSettings androidSettings = fln.AndroidInitializationSettings('@mipmap/ic_launcher');
    const fln.InitializationSettings initSettings = fln.InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);
    await _plugin
        .resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  int _taskHourId(String taskId, int hour) => taskId.hashCode ^ hour.hashCode;
  int _taskSnoozeId(String taskId) => taskId.hashCode ^ 0x5A5A5A5A;
  final int _digestId = 424242;

  Future<void> cancelAllForTask(String taskId) async {
    if (kIsWeb) return;
    for (int h = 9; h <= 17; h++) {
      await _plugin.cancel(_taskHourId(taskId, h));
    }
    await _plugin.cancel(_taskSnoozeId(taskId));
  }

  Future<void> scheduleForTaskToday(TaskItem t) async {
    if (kIsWeb) return;
    if (t.status == TaskStatus.done) return;

    final now = tz.TZDateTime.now(tz.local);
    final today = DateTime(now.year, now.month, now.day);

    if (t.muteForDate != null &&
        DateTime(t.muteForDate!.year, t.muteForDate!.month, t.muteForDate!.day) == today) {
      return;
    }

    if (t.snoozeUntil != null) {
      final s = t.snoozeUntil!;
      if (DateTime(s.year, s.month, s.day) == today && s.isAfter(now) && s.hour <= 17) {
        await _plugin.zonedSchedule(
          _taskSnoozeId(t.id),
          'Nhắc việc (Snooze): ${t.title}',
          'Trạng thái: ${statusLabel(t.status)} — bấm để mở',
          tz.TZDateTime(tz.local, s.year, s.month, s.day, s.hour, s.minute),
          const fln.NotificationDetails(android: _tasksChannel),
          androidScheduleMode: fln.AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: fln.UILocalNotificationDateInterpretation.absoluteTime,
        );
        return;
      }
    }

    for (int hour = 9; hour <= 17; hour++) {
      final schTime = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
      if (schTime.isBefore(now)) continue;
      await _plugin.zonedSchedule(
        _taskHourId(t.id, hour),
        'Nhắc việc: ${t.title}',
        'Trạng thái: ${statusLabel(t.status)} — bấm để mở',
        schTime,
        const fln.NotificationDetails(android: _tasksChannel),
        androidScheduleMode: fln.AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: fln.UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: fln.DateTimeComponents.time,
      );
    }
  }

  Future<void> scheduleDailyDigest() async {
    if (kIsWeb) return;
    final now = tz.TZDateTime.now(tz.local);
    final nine = tz.TZDateTime(tz.local, now.year, now.month, now.day, 9);
    await _plugin.zonedSchedule(
      _digestId,
      'Tổng kết công việc',
      'Mở ứng dụng để xem việc cần làm hôm nay',
      nine.isAfter(now) ? nine : nine.add(const Duration(days: 1)),
      const fln.NotificationDetails(android: _digestChannel),
      androidScheduleMode: fln.AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: fln.UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: fln.DateTimeComponents.time,
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ghi chú công việc',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<TaskItem> tasks = [];
  TaskStatus? filter;
  bool showOnlyToday = false;
  String q = '';
  bool showSearch = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    tasks = await TaskStore.instance.load();
    setState(() {});
    await _rescheduleToday();
  }

  Future<void> _persist() async => TaskStore.instance.save(tasks);

  Future<void> _rescheduleToday() async {
    for (final t in tasks) {
      await NotificationService.instance.cancelAllForTask(t.id);
    }
    for (final t in tasks) {
      await NotificationService.instance.scheduleForTaskToday(t);
    }
    await NotificationService.instance.scheduleDailyDigest();
  }

  List<TaskItem> get _filtered {
    var list = tasks.toList();
    if (filter != null) list = list.where((e) => e.status == filter).toList();
    if (showOnlyToday) {
      final now = DateTime.now();
      final d0 = DateTime(now.year, now.month, now.day);
      final d1 = d0.add(const Duration(days: 1));
      list = list.where((e) => e.createdAt.isAfter(d0) && e.createdAt.isBefore(d1)).toList();
    }
    if (q.trim().isNotEmpty) {
      final k = q.toLowerCase();
      list = list.where((e) {
        final haystack = (e.title + ' ' + e.details + ' ' + e.tags.join(' ')).toLowerCase();
        return haystack.contains(k);
      }).toList();
    }
    list.sort((a, b) {
      final st = a.status.index.compareTo(b.status.index);
      if (st != 0) return st;
      int overdueA = _isOverdue(a) ? 1 : 0;
      int overdueB = _isOverdue(b) ? 1 : 0;
      if (overdueA != overdueB) return overdueB - overdueA;
      final pri = b.priority.index.compareTo(a.priority.index);
      if (pri != 0) return pri;
      if (a.dueDate != null && b.dueDate != null) return a.dueDate!.compareTo(b.dueDate!);
      if (a.dueDate != null) return -1;
      if (b.dueDate != null) return 1;
      return a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  bool _isMutedToday(TaskItem t) {
    if (t.muteForDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final m = DateTime(t.muteForDate!.year, t.muteForDate!.month, t.muteForDate!.day);
    return m == today;
  }

  bool _isOverdue(TaskItem t) {
    if (t.dueDate == null || t.status == TaskStatus.done) return false;
    final now = DateTime.now();
    return t.dueDate!.isBefore(DateTime(now.year, now.month, now.day, 23, 59));
  }

  void _addOrEdit([TaskItem? edit]) async {
    final res = await Navigator.of(context).push<TaskItem>(
      MaterialPageRoute(builder: (_) => EditPage(item: edit)),
    );
    if (res != null) {
      final idx = tasks.indexWhere((t) => t.id == res.id);
      if (idx >= 0) {
        final old = tasks[idx];
        tasks[idx] = res;
        if (old.repeat != RepeatFreq.none && res.status == TaskStatus.done) {
          _spawnNextOccurrence(old);
        }
      } else {
        tasks.add(res);
      }
      await _persist();
      await _rescheduleToday();
      setState(() {});
    }
  }

  void _spawnNextOccurrence(TaskItem t) {
    DateTime base = t.dueDate ?? DateTime.now();
    DateTime next = base;
    switch (t.repeat) {
      case RepeatFreq.daily:
        next = base.add(const Duration(days: 1));
        break;
      case RepeatFreq.workdays:
        do {
          next = next.add(const Duration(days: 1));
        } while (next.weekday >= DateTime.saturday);
        break;
      case RepeatFreq.weekly:
        next = base.add(const Duration(days: 7));
        break;
      case RepeatFreq.none:
        return;
    }
    tasks.add(TaskItem(
      id: 't_${DateTime.now().microsecondsSinceEpoch}',
      title: t.title,
      details: t.details,
      status: TaskStatus.todo,
      createdAt: DateTime.now(),
      dueDate: next,
      priority: t.priority,
      tags: [...t.tags],
      repeat: t.repeat,
      history: [StatusEvent(TaskStatus.todo, DateTime.now())],
    ));
  }

  void _toggleMuteToday(TaskItem t) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final muted = t.muteForDate != null &&
        DateTime(t.muteForDate!.year, t.muteForDate!.month, t.muteForDate!.day) == today;
    t.muteForDate = muted ? null : today;
    t.snoozeUntil = null;
    await _persist();
    await _rescheduleToday();
    setState(() {});
  }

  void _snooze(TaskItem t, Duration d) async {
    final n = DateTime.now().add(d);
    t.snoozeUntil = n;
    await _persist();
    await _rescheduleToday();
    setState(() {});
  }

  void _changeStatus(TaskItem t, TaskStatus s) async {
    if (t.status == s) return;
    t.status = s;
    t.history.add(StatusEvent(s, DateTime.now()));
    if (s == TaskStatus.done) {
      t.completedAt = DateTime.now();
    } else {
      t.completedAt = null;
    }
    await _persist();
    await _rescheduleToday();
    setState(() {});
  }

  void _delete(TaskItem t) async {
    tasks.removeWhere((e) => e.id == t.id);
    await NotificationService.instance.cancelAllForTask(t.id);
    await _persist();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ghi chú công việc'),
        bottom: showSearch
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm tiêu đề, chi tiết, tag...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    onChanged: (v) => setState(() => q = v),
                  ),
                ),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'Tìm kiếm',
            onPressed: () => setState(() => showSearch = !showSearch),
            icon: const Icon(Icons.search),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'all') filter = null;
              if (v == 'todo') filter = TaskStatus.todo;
              if (v == 'doing') filter = TaskStatus.doing;
              if (v == 'done') filter = TaskStatus.done;
              if (v == 'today') showOnlyToday = !showOnlyToday;
              setState(() {});
            },
            itemBuilder: (c) => [
              const PopupMenuItem(value: 'all', child: Text('Tất cả')),
              const PopupMenuItem(value: 'todo', child: Text('Chưa làm')),
              const PopupMenuItem(value: 'doing', child: Text('Đang làm')),
              const PopupMenuItem(value: 'done', child: Text('Đã xong')),
              PopupMenuItem(value: 'today', child: Text(showOnlyToday ? 'Bỏ lọc “Hôm nay”' : 'Chỉ hiện việc tạo hôm nay')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEdit(),
        child: const Icon(Icons.add),
      ),
      body: _filtered.isEmpty
          ? const Center(child: Text('Chưa có công việc nào. Bấm + để thêm'))
          : ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (c, i) {
                final t = _filtered[i];
                final df = DateFormat('dd/MM/yyyy HH:mm');
                final mutedToday = _isMutedToday(t);
                final overdue = _isOverdue(t);
                return Card(
                  margin: const EdgeInsets.all(8),
                  child: ListTile(
                    leading: Icon(Icons.circle, color: priorityColor(t.priority)),
                    title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        if (t.details.isNotEmpty)
                          Text(t.details, maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          _chip('Trạng thái: ${statusLabel(t.status)}'),
                          if (t.dueDate != null)
                            _chip(overdue ? 'Quá hạn: ${df.format(t.dueDate!)}' : 'Hạn: ${df.format(t.dueDate!)}',
                                color: overdue ? Colors.red : null),
                          _chip('Ưu tiên: ${priorityLabel(t.priority)}'),
                          if (t.tags.isNotEmpty) _chip('Tags: ${t.tags.join(', ')}'),
                          _chip('Tạo: ${df.format(t.createdAt)}'),
                          if (t.completedAt != null) _chip('Hoàn thành: ${df.format(t.completedAt!)}'),
                          if (mutedToday) _chip('Đang theo dõi (tắt nhắc hôm nay)'),
                          if (t.snoozeUntil != null)
                            _chip('Snooze đến: ${df.format(t.snoozeUntil!)}'),
                        ])
                      ],
                    ),
                    onTap: () => _addOrEdit(t),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'todo') _changeStatus(t, TaskStatus.todo);
                        if (v == 'doing') _changeStatus(t, TaskStatus.doing);
                        if (v == 'done') _changeStatus(t, TaskStatus.done);
                        if (v == 'mute') _toggleMuteToday(t);
                        if (v == 'history') _showHistory(t);
                        if (v == 'delete') _delete(t);
                        if (v == 's10') _snooze(t, const Duration(minutes: 10));
                        if (v == 's60') _snooze(t, const Duration(hours: 1));
                        if (v == 's9tom') {
                          final now = DateTime.now();
                          final n9 = DateTime(now.year, now.month, now.day + 1, 9);
                          t.snoozeUntil = n9;
                          _persist().then((_) => _rescheduleToday());
                          setState(() {});
                        }
                      },
                      itemBuilder: (c) => [
                        const PopupMenuItem(value: 'todo', child: Text('Đặt "Chưa làm"')),
                        const PopupMenuItem(value: 'doing', child: Text('Đang làm')),
                        const PopupMenuItem(value: 'done', child: Text('Đã xong')),
                        const PopupMenuDivider(),
                        const PopupMenuItem(value: 's10', child: Text('Snooze +10 phút')),
                        const PopupMenuItem(value: 's60', child: Text('Snooze +1 giờ')),
                        const PopupMenuItem(value: 's9tom', child: Text('Snooze đến 9:00 mai')),
                        const PopupMenuDivider(),
                        const PopupMenuItem(value: 'mute', child: Text('Tắt thông báo hôm nay (Đang theo dõi)')),
                        const PopupMenuItem(value: 'history', child: Text('Lịch sử công việc')),
                        const PopupMenuItem(value: 'delete', child: Text('Xoá')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showHistory(TaskItem t) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) {
        final items = t.history.reversed.toList();
        return Padding(
          padding: const EdgeInsets.all(12),
          child: items.isEmpty
              ? const Text('Chưa có lịch sử')
              : ListView.separated(
                  itemBuilder: (_, i) {
                    final h = items[i];
                    return ListTile(
                      leading: const Icon(Icons.timeline),
                      title: Text('Đổi sang: ${statusLabel(h.status)}'),
                      subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(h.at)),
                    );
                  },
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemCount: items.length,
                ),
        );
      },
    );
  }

  Widget _chip(String s, {Color? color}) => Chip(
        label: Text(s),
        visualDensity: VisualDensity.compact,
        backgroundColor: color == null ? null : color.withOpacity(.12),
        side: color == null ? null : BorderSide(color: color.withOpacity(.5)),
      );
}

class EditPage extends StatefulWidget {
  final TaskItem? item;
  const EditPage({super.key, this.item});
  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  late TextEditingController titleC;
  late TextEditingController detailsC;
  late TextEditingController tagInput;
  TaskStatus status = TaskStatus.todo;
  TaskPriority priority = TaskPriority.normal;
  DateTime? dueDate;
  RepeatFreq repeat = RepeatFreq.none;
  DateTime? completedAt;
  List<String> tags = [];

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    titleC = TextEditingController(text: it?.title ?? '');
    detailsC = TextEditingController(text: it?.details ?? '');
    tagInput = TextEditingController();
    status = it?.status ?? TaskStatus.todo;
    priority = it?.priority ?? TaskPriority.normal;
    dueDate = it?.dueDate;
    repeat = it?.repeat ?? RepeatFreq.none;
    completedAt = it?.completedAt;
    tags = [...(it?.tags ?? [])];
  }

  @override
  void dispose() {
    titleC.dispose();
    detailsC.dispose();
    tagInput.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: dueDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
      helpText: 'Chọn deadline',
    );
    if (d == null) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(dueDate ?? now));
    setState(() => dueDate = DateTime(d.year, d.month, d.day, t?.hour ?? 9, t?.minute ?? 0));
  }

  void _addTag() {
    final v = tagInput.text.trim();
    if (v.isEmpty) return;
    if (!tags.contains(v)) tags.add(v);
    tagInput.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.item != null;
    final df = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Sửa công việc' : 'Thêm công việc')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(controller: titleC, decoration: const InputDecoration(labelText: 'Tiêu đề công việc')),
            const SizedBox(height: 12),
            TextField(
              controller: detailsC,
              decoration: const InputDecoration(labelText: 'Chi tiết công việc'),
              minLines: 3,
              maxLines: 6,
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Tình trạng:'),
              const SizedBox(width: 12),
              DropdownButton<TaskStatus>(
                value: status,
                items: TaskStatus.values
                    .map((s) => DropdownMenuItem(value: s, child: Text(statusLabel(s))))
                    .toList(),
                onChanged: (v) => setState(() => status = v ?? TaskStatus.todo),
              ),
              const Spacer(),
              const Text('Ưu tiên:'),
              const SizedBox(width: 12),
              DropdownButton<TaskPriority>(
                value: priority,
                items: TaskPriority.values
                    .map((p) => DropdownMenuItem(value: p, child: Text(priorityLabel(p))))
                    .toList(),
                onChanged: (v) => setState(() => priority = v ?? TaskPriority.normal),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDueDate,
                  icon: const Icon(Icons.event),
                  label: Text(dueDate == null ? 'Chọn deadline' : 'Hạn: ${df.format(dueDate!)}'),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<RepeatFreq>(
                value: repeat,
                items: const [
                  DropdownMenuItem(value: RepeatFreq.none, child: Text('Không lặp')),
                  DropdownMenuItem(value: RepeatFreq.daily, child: Text('Hàng ngày')),
                  DropdownMenuItem(value: RepeatFreq.workdays, child: Text('Ngày làm việc (T2–T6)')),
                  DropdownMenuItem(value: RepeatFreq.weekly, child: Text('Hàng tuần')),
                ],
                onChanged: (v) => setState(() => repeat = v ?? RepeatFreq.none),
              ),
            ]),
            const SizedBox(height: 12),
            const Text('Tags'),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in tags)
                Chip(label: Text(t), onDeleted: () => setState(() => tags.remove(t))),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: tagInput,
                  decoration: InputDecoration(
                    hintText: 'Thêm tag và Enter',
                    suffixIcon: IconButton(onPressed: _addTag, icon: const Icon(Icons.add)),
                  ),
                  onSubmitted: (_) => _addTag(),
                ),
              ),
            ]),
            const SizedBox(height: 24),
            if (status == TaskStatus.done)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text('Hoàn thành: ${df.format(completedAt ?? DateTime.now())}'),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: Text(isEdit ? 'Lưu thay đổi' : 'Thêm'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final now = DateTime.now();
    final it = widget.item;
    final id = it?.id ?? 't_${now.microsecondsSinceEpoch}';

    DateTime? doneAt = completedAt;
    if (status == TaskStatus.done && doneAt == null) doneAt = now;
    if (status != TaskStatus.done) doneAt = null;

    final res = TaskItem(
      id: id,
      title: titleC.text.trim(),
      details: detailsC.text.trim(),
      status: status,
      createdAt: it?.createdAt ?? now,
      completedAt: doneAt,
      muteForDate: it?.muteForDate,
      dueDate: dueDate,
      priority: priority,
      tags: tags,
      snoozeUntil: it?.snoozeUntil,
      repeat: repeat,
      history: (it?.history ?? [])..add(StatusEvent(status, now)),
    );
    Navigator.of(context).pop(res);
  }
}
