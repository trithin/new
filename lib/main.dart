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

/* ======================= DATA MODELS ======================= */
enum TaskStatus { todo, doing, done }
enum TaskPriority { low, normal, high }

/// Kiểu lịch nhắc cho từng task
enum NotifyKind {
  none,          // không nhắc
  interval,      // nhắc theo chu kỳ mỗi N giờ trong khung [start..end]
  dailyFixed,    // 1 giờ cố định hằng ngày (HH:mm)
}

String statusLabel(TaskStatus s) => switch (s) {
  TaskStatus.todo  => 'Chưa làm',
  TaskStatus.doing => 'Đang làm',
  TaskStatus.done  => 'Đã xong',
};
String priorityLabel(TaskPriority p) => switch (p) {
  TaskPriority.low    => 'Thấp',
  TaskPriority.normal => 'Thường',
  TaskPriority.high   => 'Cao',
};
Color priorityColor(TaskPriority p) => switch (p) {
  TaskPriority.low    => Colors.blueGrey,
  TaskPriority.normal => Colors.teal,
  TaskPriority.high   => Colors.deepOrange,
};

TaskStatus statusFromString(String? s) {
  switch (s) {
    case 'doing': case 'Đang làm': return TaskStatus.doing;
    case 'done':  case 'Đã xong':  return TaskStatus.done;
    default:                       return TaskStatus.todo;
  }
}
TaskPriority priorityFromString(String? s) {
  switch (s) {
    case 'low':  case 'Thấp':   return TaskPriority.low;
    case 'high': case 'Cao':    return TaskPriority.high;
    default:                    return TaskPriority.normal;
  }
}
NotifyKind notifyKindFromString(String? s) {
  switch (s) {
    case 'interval':   return NotifyKind.interval;
    case 'dailyFixed': return NotifyKind.dailyFixed;
    default:           return NotifyKind.none;
  }
}

/// Bản ghi lịch sử trạng thái
class StatusEvent {
  final TaskStatus status;
  final DateTime at;
  StatusEvent(this.status, this.at);

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'at': at.toIso8601String(),
  };
  factory StatusEvent.fromJson(Map<String, dynamic> j) =>
      StatusEvent(statusFromString(j['status']), DateTime.parse(j['at']));
}

/// Cấu hình thông báo cho task
class NotifyConfig {
  NotifyKind kind;
  // interval
  int intervalHours;         // 1,2,3,4,6,8,12,...
  int startHour;             // 0..23
  int endHour;               // 0..23 (>= startHour trong cùng ngày)
  // daily fixed
  int dailyHour;             // 0..23
  int dailyMinute;           // 0..59
  // tuỳ chọn: chỉ ngày làm việc
  bool workdaysOnly;

  NotifyConfig.interval({
    required this.intervalHours,
    required this.startHour,
    required this.endHour,
    this.workdaysOnly = false,
  }) : kind = NotifyKind.interval,
       dailyHour = 9, dailyMinute = 0;

  NotifyConfig.daily({required this.dailyHour, required this.dailyMinute, this.workdaysOnly = false})
      : kind = NotifyKind.dailyFixed,
        intervalHours = 2, startHour = 9, endHour = 17;

  NotifyConfig.none() : kind = NotifyKind.none,
    intervalHours = 2, startHour = 9, endHour = 17,
    dailyHour = 9, dailyMinute = 0, workdaysOnly = false;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'intervalHours': intervalHours,
    'startHour': startHour,
    'endHour': endHour,
    'dailyHour': dailyHour,
    'dailyMinute': dailyMinute,
    'workdaysOnly': workdaysOnly,
  };

  factory NotifyConfig.fromJson(Map<String, dynamic>? j) {
    if (j == null) return NotifyConfig.none();
    final k = notifyKindFromString(j['kind']);
    final workdays = (j['workdaysOnly'] ?? false) == true;
    if (k == NotifyKind.interval) {
      return NotifyConfig.interval(
        intervalHours: (j['intervalHours'] ?? 2) as int,
        startHour: (j['startHour'] ?? 9) as int,
        endHour: (j['endHour'] ?? 17) as int,
        workdaysOnly: workdays,
      );
    }
    if (k == NotifyKind.dailyFixed) {
      return NotifyConfig.daily(
        dailyHour: (j['dailyHour'] ?? 9) as int,
        dailyMinute: (j['dailyMinute'] ?? 0) as int,
        workdaysOnly: workdays,
      );
    }
    return NotifyConfig.none();
  }

  String summary() {
    switch (kind) {
      case NotifyKind.none:
        return 'Không nhắc';
      case NotifyKind.interval:
        final wd = workdaysOnly ? ' (T2–T6)' : '';
        return 'Mỗi $intervalHours giờ • $startHour:00–$endHour:00$wd';
      case NotifyKind.dailyFixed:
        final wd = workdaysOnly ? ' (T2–T6)' : '';
        final hm = '${dailyHour.toString().padLeft(2,'0')}:${dailyMinute.toString().padLeft(2,'0')}';
        return 'Mỗi ngày $hm$wd';
    }
  }
}

class TaskItem {
  final String id;
  String title;
  String details;
  TaskStatus status;
  TaskPriority priority;
  DateTime createdAt;
  DateTime? completedAt;
  DateTime? dueDate;

  // kiểm soát nhắc trong ngày
  DateTime? muteForDate;   // nếu = hôm nay → im lặng hôm nay
  DateTime? snoozeUntil;   // snooze 1 lần (ghi thời điểm)

  // tags + lịch sử
  List<String> tags;
  List<StatusEvent> history;

  // cấu hình nhắc
  NotifyConfig notify;

  TaskItem({
    required this.id,
    required this.title,
    required this.details,
    required this.status,
    required this.priority,
    required this.createdAt,
    this.completedAt,
    this.dueDate,
    this.muteForDate,
    this.snoozeUntil,
    List<String>? tags,
    List<StatusEvent>? history,
    required this.notify,
  }) : tags = tags ?? [], history = history ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'details': details,
    'status': status.name,
    'priority': priority.name,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'dueDate': dueDate?.toIso8601String(),
    'muteForDate': muteForDate == null ? null : DateTime(muteForDate!.year, muteForDate!.month, muteForDate!.day).toIso8601String(),
    'snoozeUntil': snoozeUntil?.toIso8601String(),
    'tags': tags,
    'history': history.map((e) => e.toJson()).toList(),
    'notify': notify.toJson(),
  };

  factory TaskItem.fromJson(Map<String, dynamic> j) => TaskItem(
    id: j['id'],
    title: j['title'] ?? '',
    details: j['details'] ?? '',
    status: statusFromString(j['status']),
    priority: priorityFromString(j['priority']),
    createdAt: DateTime.parse(j['createdAt']),
    completedAt: j['completedAt'] == null ? null : DateTime.parse(j['completedAt']),
    dueDate: j['dueDate'] == null ? null : DateTime.parse(j['dueDate']),
    muteForDate: j['muteForDate'] == null ? null : DateTime.parse(j['muteForDate']),
    snoozeUntil: j['snoozeUntil'] == null ? null : DateTime.parse(j['snoozeUntil']),
    tags: ((j['tags'] ?? []) as List).map((e) => '$e').toList(),
    history: ((j['history'] ?? []) as List).map((e) => StatusEvent.fromJson(e)).toList(),
    notify: NotifyConfig.fromJson(j['notify']),
  );
}

class TaskStore {
  static const _k = 'tasks_v3';
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

/* ======================= NOTIFICATIONS ======================= */
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final fln.FlutterLocalNotificationsPlugin _plugin = fln.FlutterLocalNotificationsPlugin();

  static const _tasksChannel = fln.AndroidNotificationDetails(
    'tasks_channel',
    'Nhắc công việc',
    channelDescription: 'Nhắc theo cấu hình từng công việc',
    importance: fln.Importance.high,
    priority: fln.Priority.high,
  );

  Future<void> init() async {
    if (kIsWeb) return;
    const fln.AndroidInitializationSettings androidSettings =
        fln.AndroidInitializationSettings('@mipmap/ic_launcher');
    const fln.InitializationSettings initSettings =
        fln.InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);
    await _plugin
        .resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  // tạo id từ taskId + HHmm
  int _id(String taskId, int hhmm) => taskId.hashCode ^ hhmm.hashCode;
  int _snoozeId(String taskId) => taskId.hashCode ^ 0x1A2B3C;

  Future<void> cancelAllForTask(String taskId) async {
    if (kIsWeb) return;
    // hủy "snooze" + tất cả khung giờ 00:00..23:59 (chúng ta tạo id = task ^ HHmm)
    await _plugin.cancel(_snoozeId(taskId));
    for (int h = 0; h < 24; h++) {
      final base = h * 100;
      for (final m in [0, 15, 30, 45]) {
        await _plugin.cancel(_id(taskId, base + m));
      }
    }
  }

  /// Lập lịch theo NotifyConfig của task
  Future<void> scheduleByConfig(TaskItem t) async {
    if (kIsWeb) return;
    if (t.status == TaskStatus.done) return;

    final now = tz.TZDateTime.now(tz.local);
    final today = DateTime(now.year, now.month, now.day);

    // mute hôm nay?
    if (t.muteForDate != null &&
        DateTime(t.muteForDate!.year, t.muteForDate!.month, t.muteForDate!.day) == today) {
      return;
    }

    // nếu có snooze (1 lần)
    if (t.snoozeUntil != null) {
      final s = t.snoozeUntil!;
      final sTz = tz.TZDateTime(tz.local, s.year, s.month, s.day, s.hour, s.minute);
      if (sTz.isAfter(now)) {
        await _plugin.zonedSchedule(
          _snoozeId(t.id),
          'Nhắc việc (Snooze): ${t.title}',
          'Trạng thái: ${statusLabel(t.status)} — bấm để mở',
          sTz,
          const fln.NotificationDetails(android: _tasksChannel),
          androidScheduleMode: fln.AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: fln.UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }

    final details = const fln.NotificationDetails(android: _tasksChannel);

    // Helper tạo 1 lịch nhắc (và lặp hằng ngày)
    Future<void> _scheduleDaily(int hour, int minute) async {
      // nếu chỉ ngày làm việc: bỏ T7 CN
      if (t.notify.workdaysOnly) {
        final wd = now.weekday;
        if (wd == DateTime.saturday || wd == DateTime.sunday) return;
      }
      final scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
      final when = scheduled.isAfter(now) ? scheduled : scheduled.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        _id(t.id, hour * 100 + minute),
        'Nhắc việc: ${t.title}',
        'Trạng thái: ${statusLabel(t.status)} — bấm để mở',
        when,
        details,
        androidScheduleMode: fln.AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: fln.UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: fln.DateTimeComponents.time, // lặp hằng ngày cùng giờ
      );
    }

    switch (t.notify.kind) {
      case NotifyKind.none:
        return;
      case NotifyKind.dailyFixed:
        await _scheduleDaily(t.notify.dailyHour, t.notify.dailyMinute);
        return;
      case NotifyKind.interval:
        // các mốc HH:00 trong khung giờ [start..end] cách nhau intervalHours
        int h = t.notify.startHour;
        while (h <= t.notify.endHour) {
          await _scheduleDaily(h, 0);
          h += t.notify.intervalHours;
          if (h > 23) break;
        }
        return;
    }
  }
}

/* ======================= APP UI ======================= */
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ghi chú công việc',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        cardTheme: CardTheme(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(borderSide: BorderSide.none),
          filled: true,
        ),
      ),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int idx = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [const TaskListPage(), const HistoryPage()];
    return Scaffold(
      body: pages[idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (v) => setState(() => idx = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.checklist), label: 'Danh sách'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Lịch sử'),
        ],
      ),
    );
  }
}

/* ======================= TASK LIST ======================= */
class TaskListPage extends StatefulWidget {
  const TaskListPage({super.key});
  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  List<TaskItem> tasks = [];
  TaskStatus? filter;
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
    await _rescheduleAll();
  }

  Future<void> _persist() async => TaskStore.instance.save(tasks);

  Future<void> _rescheduleAll() async {
    for (final t in tasks) {
      await NotificationService.instance.cancelAllForTask(t.id);
    }
    for (final t in tasks) {
      await NotificationService.instance.scheduleByConfig(t);
    }
  }

  List<TaskItem> get _filtered {
    var list = tasks.toList();
    if (filter != null) list = list.where((e) => e.status == filter).toList();
    if (q.trim().isNotEmpty) {
      final k = q.toLowerCase();
      list = list.where((e) {
        final hay = '${e.title} ${e.details} ${e.tags.join(" ")}'.toLowerCase();
        return hay.contains(k);
      }).toList();
    }
    list.sort((a, b) {
      // Ưu tiên: chưa làm → đang làm → đã xong; rồi ưu tiên High trước
      final st = a.status.index.compareTo(b.status.index);
      if (st != 0) return st;
      final pr = b.priority.index.compareTo(a.priority.index);
      if (pr != 0) return pr;
      // gần deadline trước
      if (a.dueDate != null && b.dueDate != null) return a.dueDate!.compareTo(b.dueDate!);
      if (a.dueDate != null) return -1;
      if (b.dueDate != null) return 1;
      return a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  void _addOrEdit([TaskItem? edit]) async {
    final res = await Navigator.of(context).push<TaskItem>(
      MaterialPageRoute(builder: (_) => EditPage(item: edit)),
    );
    if (res != null) {
      final idx = tasks.indexWhere((t) => t.id == res.id);
      if (idx >= 0) {
        tasks[idx] = res;
      } else {
        tasks.add(res);
      }
      await _persist();
      await _rescheduleAll();
      setState(() {});
    }
  }

  void _changeStatus(TaskItem t, TaskStatus s) async {
    if (t.status == s) return;
    t.status = s;
    t.history.add(StatusEvent(s, DateTime.now()));
    t.completedAt = s == TaskStatus.done ? DateTime.now() : null;
    await _persist();
    await _rescheduleAll();
    setState(() {});
  }

  void _toggleMuteToday(TaskItem t) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isMuted = t.muteForDate != null &&
        DateTime(t.muteForDate!.year, t.muteForDate!.month, t.muteForDate!.day) == today;
    t.muteForDate = isMuted ? null : today;
    t.snoozeUntil = null;
    await _persist();
    await _rescheduleAll();
    setState(() {});
  }

  void _snooze(TaskItem t, Duration d) async {
    t.snoozeUntil = DateTime.now().add(d);
    await _persist();
    await _rescheduleAll();
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
    final df = DateFormat('dd/MM/yyyy HH:mm');
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          snap: true,
          title: const Text('Ghi chú công việc'),
          actions: [
            IconButton(
              tooltip: 'Tìm kiếm',
              onPressed: () => setState(() => showSearch = !showSearch),
              icon: const Icon(Icons.search),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => setState(() {
                if (v == 'all')  filter = null;
                if (v == 'todo') filter = TaskStatus.todo;
                if (v == 'doing') filter = TaskStatus.doing;
                if (v == 'done')  filter = TaskStatus.done;
              }),
              itemBuilder: (c) => const [
                PopupMenuItem(value: 'all',  child: Text('Tất cả')),
                PopupMenuItem(value: 'todo', child: Text('Chưa làm')),
                PopupMenuItem(value: 'doing', child: Text('Đang làm')),
                PopupMenuItem(value: 'done', child: Text('Đã xong')),
              ],
            ),
          ],
          bottom: showSearch
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(60),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Tìm theo tên, chi tiết, tag...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) => setState(() => q = v),
                    ),
                  ),
                )
              : null,
        ),
        if (_filtered.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('Chưa có công việc nào. Bấm nút + để thêm.')),
          )
        else
          SliverList.builder(
            itemCount: _filtered.length,
            itemBuilder: (c, i) {
              final t = _filtered[i];
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _addOrEdit(t),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 6, height: 56,
                            decoration: BoxDecoration(
                              color: priorityColor(t.priority),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(t.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700, fontSize: 16,
                                          )),
                                    ),
                                    _statusPill(t.status),
                                  ],
                                ),
                                if (t.details.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(t.details, maxLines: 2, overflow: TextOverflow.ellipsis),
                                ],
                                const SizedBox(height: 8),
                                Wrap(spacing: 6, runSpacing: 6, children: [
                                  _chip(Icons.schedule, t.dueDate == null
                                      ? 'Không hạn'
                                      : 'Hạn: ${df.format(t.dueDate!)}'),
                                  _chip(Icons.notifications_active, t.notify.summary()),
                                  if (t.snoozeUntil != null)
                                    _chip(Icons.snooze, 'Snooze: ${df.format(t.snoozeUntil!)}'),
                                  if (t.muteForDate != null &&
                                      DateTime.now().difference(t.muteForDate!).inDays == 0)
                                    _chip(Icons.visibility_off, 'Tắt nhắc hôm nay'),
                                ]),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'todo')  _changeStatus(t, TaskStatus.todo);
                              if (v == 'doing') _changeStatus(t, TaskStatus.doing);
                              if (v == 'done')  _changeStatus(t, TaskStatus.done);
                              if (v == 'mute')  _toggleMuteToday(t);
                              if (v == 's10')   _snooze(t, const Duration(minutes: 10));
                              if (v == 's60')   _snooze(t, const Duration(hours: 1));
                              if (v == 'delete') _delete(t);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'todo',  child: Text('Đặt "Chưa làm"')),
                              PopupMenuItem(value: 'doing', child: Text('Đang làm')),
                              PopupMenuItem(value: 'done',  child: Text('Đã xong')),
                              PopupMenuDivider(),
                              PopupMenuItem(value: 's10',   child: Text('Snooze +10 phút')),
                              PopupMenuItem(value: 's60',   child: Text('Snooze +1 giờ')),
                              PopupMenuItem(value: 'mute',  child: Text('Tắt nhắc hôm nay')),
                              PopupMenuDivider(),
                              PopupMenuItem(value: 'delete', child: Text('Xoá')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _chip(IconData i, String s) => Chip(
        avatar: Icon(i, size: 16),
        label: Text(s),
        visualDensity: VisualDensity.compact,
      );

  Widget _statusPill(TaskStatus s) {
    final c = switch (s) {
      TaskStatus.todo  => Colors.orange,
      TaskStatus.doing => Colors.blue,
      TaskStatus.done  => Colors.green,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: c.withOpacity(.5)),
      ),
      child: Text(statusLabel(s), style: TextStyle(color: c, fontWeight: FontWeight.w600)),
    );
  }
}

/* ======================= HISTORY PAGE ======================= */
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<TaskItem> tasks = [];
  String q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    tasks = await TaskStore.instance.load();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final all = <({TaskItem t, StatusEvent e})>[];
    for (final t in tasks) {
      for (final e in t.history) {
        all.add((t: t, e: e));
      }
    }
    all.sort((a, b) => b.e.at.compareTo(a.e.at));

    final filtered = q.trim().isEmpty
        ? all
        : all.where((x) {
            final k = q.toLowerCase();
            return ('${x.t.title} ${x.t.details} ${x.t.tags.join(" ")}'.toLowerCase().contains(k));
          }).toList();

    final df = DateFormat('dd/MM/yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm trong lịch sử theo tên/chi tiết/tag...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
        ),
      ),
      body: filtered.isEmpty
          ? const Center(child: Text('Chưa có lịch sử'))
          : ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final x = filtered[i];
                return ListTile(
                  leading: Icon(Icons.timeline, color: priorityColor(x.t.priority)),
                  title: Text(x.t.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('→ ${statusLabel(x.e.status)} • ${df.format(x.e.at)}'),
                  trailing: _statusPillMini(x.e.status),
                );
              },
            ),
    );
  }

  Widget _statusPillMini(TaskStatus s) {
    final c = switch (s) {
      TaskStatus.todo  => Colors.orange,
      TaskStatus.doing => Colors.blue,
      TaskStatus.done  => Colors.green,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: c.withOpacity(.5)),
      ),
      child: Text(statusLabel(s), style: TextStyle(color: c, fontWeight: FontWeight.w600)),
    );
  }
}

/* ======================= EDIT PAGE ======================= */
class EditPage extends StatefulWidget {
  final TaskItem? item;
  const EditPage({super.key, this.item});
  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  late TextEditingController titleC;
  late TextEditingController detailsC;
  late TextEditingController tagC;

  TaskStatus status = TaskStatus.todo;
  TaskPriority priority = TaskPriority.normal;
  DateTime? dueDate;
  List<String> tags = [];

  // Notify controls
  NotifyKind kind = NotifyKind.interval;
  int intervalHours = 2;
  int startHour = 9;
  int endHour = 17;
  TimeOfDay dailyTime = const TimeOfDay(hour: 9, minute: 0);
  bool workdaysOnly = false;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    titleC = TextEditingController(text: it?.title ?? '');
    detailsC = TextEditingController(text: it?.details ?? '');
    tagC = TextEditingController();
    status = it?.status ?? TaskStatus.todo;
    priority = it?.priority ?? TaskPriority.normal;
    dueDate = it?.dueDate;
    tags = [...(it?.tags ?? [])];

    final n = it?.notify ?? NotifyConfig.interval(intervalHours: 2, startHour: 9, endHour: 17);
    kind = n.kind;
    intervalHours = n.intervalHours;
    startHour = n.startHour;
    endHour = n.endHour;
    dailyTime = TimeOfDay(hour: n.dailyHour, minute: n.dailyMinute);
    workdaysOnly = n.workdaysOnly;
  }

  @override
  void dispose() {
    titleC.dispose();
    detailsC.dispose();
    tagC.dispose();
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
    final v = tagC.text.trim();
    if (v.isEmpty) return;
    if (!tags.contains(v)) tags.add(v);
    tagC.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.item != null;
    final df = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Sửa công việc' : 'Thêm công việc')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save,
        icon: const Icon(Icons.save),
        label: Text(isEdit ? 'Lưu' : 'Thêm'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: titleC, decoration: const InputDecoration(labelText: 'Tiêu đề công việc')),
          const SizedBox(height: 12),
          TextField(
            controller: detailsC,
            decoration: const InputDecoration(labelText: 'Chi tiết công việc'),
            minLines: 3, maxLines: 6,
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Tình trạng:'), const SizedBox(width: 12),
            DropdownButton<TaskStatus>(
              value: status,
              items: TaskStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(statusLabel(s)))).toList(),
              onChanged: (v) => setState(() => status = v ?? TaskStatus.todo),
            ),
            const Spacer(),
            const Text('Ưu tiên:'), const SizedBox(width: 12),
            DropdownButton<TaskPriority>(
              value: priority,
              items: TaskPriority.values.map((p) => DropdownMenuItem(value: p, child: Text(priorityLabel(p)))).toList(),
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
          ]),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text('Thông báo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<NotifyKind>(
            segments: const [
              ButtonSegment(value: NotifyKind.interval, label: Text('Mỗi N giờ'), icon: Icon(Icons.av_timer)),
              ButtonSegment(value: NotifyKind.dailyFixed, label: Text('Giờ cố định'), icon: Icon(Icons.access_time)),
              ButtonSegment(value: NotifyKind.none,     label: Text('Tắt'),         icon: Icon(Icons.notifications_off)),
            ],
            selected: {kind},
            onSelectionChanged: (s) => setState(() => kind = s.first),
          ),
          const SizedBox(height: 8),
          if (kind == NotifyKind.interval) _intervalEditor(),
          if (kind == NotifyKind.dailyFixed) _dailyEditor(),
          Row(children: [
            Checkbox(value: workdaysOnly, onChanged: (v) => setState(() => workdaysOnly = v ?? false)),
            const Text('Chỉ nhắc ngày làm việc (T2–T6)'),
          ]),
          const Divider(height: 32),
          const Text('Tags'),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in tags) Chip(label: Text(t), onDeleted: () => setState(() => tags.remove(t))),
            SizedBox(
              width: 200,
              child: TextField(
                controller: tagC,
                decoration: InputDecoration(
                  hintText: 'Thêm tag rồi Enter',
                  suffixIcon: IconButton(onPressed: _addTag, icon: const Icon(Icons.add)),
                ),
                onSubmitted: (_) => _addTag(),
              ),
            ),
          ]),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _intervalEditor() {
    return Column(
      children: [
        Row(children: [
          const Text('Chu kỳ:'),
          const SizedBox(width: 12),
          DropdownButton<int>(
            value: intervalHours,
            items: const [1,2,3,4,6,8,12].map((h) => DropdownMenuItem(value: h, child: Text('$h giờ/lần'))).toList(),
            onChanged: (v) => setState(() => intervalHours = v ?? 2),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: startHour, minute: 0));
                if (t != null) setState(() => startHour = t.hour);
              },
              child: Text('Bắt đầu: ${startHour.toString().padLeft(2,'0')}:00'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: endHour, minute: 0));
                if (t != null) setState(() => endHour = t.hour);
              },
              child: Text('Kết thúc: ${endHour.toString().padLeft(2,'0')}:00'),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _dailyEditor() {
    return Row(children: [
      Expanded(
        child: OutlinedButton(
          onPressed: () async {
            final t = await showTimePicker(context: context, initialTime: dailyTime);
            if (t != null) setState(() => dailyTime = t);
          },
          child: Text('Giờ cố định: ${dailyTime.format(context)}'),
        ),
      ),
    ]);
  }

  void _save() {
    final now = DateTime.now();
    final it = widget.item;
    final id = it?.id ?? 't_${now.microsecondsSinceEpoch}';

    final notify = switch (kind) {
      NotifyKind.none      => NotifyConfig.none(),
      NotifyKind.interval  => NotifyConfig.interval(
        intervalHours: intervalHours, startHour: startHour, endHour: endHour, workdaysOnly: workdaysOnly),
      NotifyKind.dailyFixed => NotifyConfig.daily(
        dailyHour: dailyTime.hour, dailyMinute: dailyTime.minute, workdaysOnly: workdaysOnly),
    };

    final res = TaskItem(
      id: id,
      title: titleC.text.trim(),
      details: detailsC.text.trim(),
      status: status,
      priority: priority,
      createdAt: it?.createdAt ?? now,
      completedAt: status == TaskStatus.done ? (it?.completedAt ?? now) : null,
      dueDate: dueDate,
      muteForDate: it?.muteForDate,
      snoozeUntil: it?.snoozeUntil,
      tags: tags,
      history: (it?.history ?? [])..add(StatusEvent(status, now)),
      notify: notify,
    );
    Navigator.of(context).pop(res);
  }
}
