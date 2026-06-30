import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'holiday_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/cupertino.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  final prefs = await SharedPreferences.getInstance();

  final savedThemeIndex = prefs.getInt('theme_mode');
  if (savedThemeIndex != null) {
    themeModeNotifier.value = ThemeMode.values[savedThemeIndex];
  }

  final savedColorValue = prefs.getInt('theme_color');
  if (savedColorValue != null) {
    themeColorNotifier.value = Color(savedColorValue);
  }

  runApp(const BusinessCalendarApp());
}

ValueNotifier<Color> themeColorNotifier = ValueNotifier(Colors.blueAccent);
ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.system);

class BusinessCalendarApp extends StatelessWidget {
  const BusinessCalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return ValueListenableBuilder(
          valueListenable: themeColorNotifier,
          builder: (context, color, _) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('ja', 'JP'),
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('ja', 'JP')],
              themeMode: mode,
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
              home: const CalendarScreen(),
            );
          },
        );
      },
    );
  }
}

class TaskItem {
  String text;
  bool done;
  bool isAllDay;
  int startHour;
  int startMinute;
  int endHour;
  int endMinute;

  TaskItem({
    required this.text,
    this.done = false,
    this.isAllDay = false,
    this.startHour = 9,
    this.startMinute = 0,
    this.endHour = 18,
    this.endMinute = 0,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'done': done,
    'isAllDay': isAllDay,
    'startHour': startHour,
    'startMinute': startMinute,
    'endHour': endHour,
    'endMinute': endMinute,
  };

  factory TaskItem.fromJson(Map<String, dynamic> json) => TaskItem(
    text: json['text'],
    done: json['done'] ?? false,
    isAllDay: json['isAllDay'] ?? true,
    startHour: json['startHour'] ?? 9,
    startMinute: json['startMinute'] ?? 0,
    endHour: json['endHour'] ?? 18,
    endMinute: json['endMinute'] ?? 0,
  );
}

class HolidayData {
  bool isHoliday;
  List<TaskItem> tasks;
  String memo;

  HolidayData({this.isHoliday = false, List<TaskItem>? tasks, this.memo = ''})
    : tasks = tasks ?? [];

  Map<String, dynamic> toJson() => {
    'isHoliday': isHoliday,
    'tasks': tasks.map((t) => t.toJson()).toList(),
    'memo': memo,
  };

  factory HolidayData.fromJson(Map<String, dynamic> json) {
    List<TaskItem> tasks = [];
    if (json['tasks'] != null) {
      tasks = (json['tasks'] as List).map((e) => TaskItem.fromJson(e)).toList();
    }
    return HolidayData(
      isHoliday: json['isHoliday'] ?? false,
      tasks: tasks,
      memo: json['memo'] ?? '',
    );
  }
}

enum DayFilter { all, withEvent, holiday }

class FixedHoliday {
  int month;
  int day;
  String title;
  FixedHoliday({required this.month, required this.day, required this.title});

  Map<String, dynamic> toJson() => {'month': month, 'day': day, 'title': title};
  factory FixedHoliday.fromJson(Map<String, dynamic> json) => FixedHoliday(
    month: json['month'],
    day: json['day'],
    title: json['title'],
  );
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  final DateTime _today = DateTime.now();
  final PageController _pageController = PageController();
  final TextEditingController _milestoneTitleController =
      TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _milestones = [];
  bool _includeWeekends = false;
  Map<DateTime, HolidayData> _holidayConfigs = {};
  List<FixedHoliday> _fixedHolidays = [];
  DayFilter _dayFilter = DayFilter.all;
  Map<String, String> _japaneseHolidays = {};
  CalendarFormat _calendarFormat = CalendarFormat.month;
  bool _isTimelineMode = false;
  DateTime _timelineBaseDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );

  // スクロール位置制御用のフラグ
  bool _needsScrollToToday = true;
  DateTime? _lastScrolledMonth;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadHolidays();
  }

  Future<void> _loadHolidays() async {
    final holidays = await HolidayService.fetchHolidays();
    if (mounted) {
      setState(() => _japaneseHolidays = holidays);
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, String> dataToSave = {};
    _holidayConfigs.forEach(
      (key, value) =>
          dataToSave[key.toIso8601String()] = jsonEncode(value.toJson()),
    );
    await prefs.setString('holiday_configs', jsonEncode(dataToSave));
    await prefs.setBool('include_weekends', _includeWeekends);
    List<String> fixedList = _fixedHolidays
        .map((e) => jsonEncode(e.toJson()))
        .toList();
    await prefs.setStringList('fixed_holidays_v2', fixedList);
  }

  Future<void> _saveMilestones() async {
    final prefs = await SharedPreferences.getInstance();
    String encodedData = jsonEncode(
      _milestones.map((m) {
        return {
          'id': m['id'],
          'title': m['title'],
          'date': (m['date'] as DateTime).toIso8601String(),
          'isRecurring': m['isRecurring'] ?? false,
          'isNotify': m['isNotify'] ?? false,
          'colorValue': m['colorValue'],
        };
      }).toList(),
    );
    await prefs.setString('saved_milestones', encodedData);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _includeWeekends = prefs.getBool('include_weekends') ?? false;
      List<String>? fixedJsonList = prefs.getStringList('fixed_holidays_v2');
      if (fixedJsonList != null) {
        _fixedHolidays = fixedJsonList
            .map((e) => FixedHoliday.fromJson(jsonDecode(e)))
            .toList();
      }
      String? jsonString = prefs.getString('holiday_configs');
      if (jsonString != null) {
        Map<String, dynamic> savedData = jsonDecode(jsonString);
        _holidayConfigs = savedData.map(
          (k, v) =>
              MapEntry(DateTime.parse(k), HolidayData.fromJson(jsonDecode(v))),
        );
      }
      String? milestonesJson = prefs.getString('saved_milestones');
      if (milestonesJson != null) {
        List<dynamic> decoded = jsonDecode(milestonesJson);
        _milestones = decoded
            .map(
              (m) => {
                'id':
                    m['id'] ??
                    (m['title'].hashCode ^
                        DateTime.parse(m['date']).millisecondsSinceEpoch),
                'title': m['title'],
                'date': DateTime.parse(m['date']),
                'isRecurring': m['isRecurring'] ?? false,
                'isNotify': m['isNotify'] ?? false,
                'colorValue': m['colorValue'],
              },
            )
            .toList();
      }
      _needsScrollToToday = true;
    });
  }

  String _dateKeyString(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  bool _isOffDay(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    if (_japaneseHolidays.containsKey(_dateKeyString(date))) return true;
    if (_fixedHolidays.any(
      (fh) => fh.month == date.month && fh.day == date.day,
    )) {
      return true;
    }
    final config = _holidayConfigs[date];
    if (config != null && config.isHoliday == true) return true;
    if (!_includeWeekends) {
      if (date.weekday == DateTime.saturday ||
          date.weekday == DateTime.sunday) {
        return true;
      }
    }
    return false;
  }

  bool _isRedLetterHoliday(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    if (_japaneseHolidays.containsKey(_dateKeyString(date))) return true;
    return _fixedHolidays.any(
      (fh) => fh.month == date.month && fh.day == date.day,
    );
  }

  Future<void> _scheduleNotification(
    int id,
    String title,
    DateTime date,
  ) async {
    final scheduledDate = tz.TZDateTime(
      tz.local,
      date.year,
      date.month,
      date.day,
      9,
    );
    if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) return;

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      '本日の重要予定',
      title,
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'milestone_channel',
          '重要日の通知',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> _cancelNotification(int id) async {
    // もし id が 32ビット整数の最大値（2147483647）を超えていたら、安全な範囲に丸める
    int safeId = id;
    if (id > 2147483647) {
      safeId = id % 100000000;
    }
    await flutterLocalNotificationsPlugin.cancel(safeId);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    DateTime firstDayOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
    DateTime lastDayOfMonth = DateTime(
      _focusedDay.year,
      _focusedDay.month + 1,
      0,
    );

    List<DateTime> businessDays = [];
    for (int i = 0; i < lastDayOfMonth.day; i++) {
      DateTime day = firstDayOfMonth.add(Duration(days: i));
      if (!_isOffDay(day)) businessDays.add(day);
    }

    DateTime lastBD = businessDays.isNotEmpty
        ? businessDays.last
        : lastDayOfMonth;
    DateTime todayDate = DateTime(_today.year, _today.month, _today.day);
    int count = businessDays.where((day) => day.isAfter(todayDate)).length;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [
                    Theme.of(context).colorScheme.surface,
                    Theme.of(context).scaffoldBackgroundColor,
                  ]
                : [Colors.blue[50]!, Colors.white],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _isTimelineMode
                    ? _buildTimelineView()
                    : Column(
                        children: [
                          _buildTopCards(count, lastBD),
                          Expanded(flex: 3, child: _buildCalendarCard(lastBD)),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.list_alt,
                                  size: 18,
                                  color: Colors.blueGrey,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '予定一覧',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.blueGrey[200]
                                        : Colors.blueGrey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: _buildBusinessDayList(businessDays),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBusinessDayList(List<DateTime> businessDays) {
    if (businessDays.isEmpty) return const Center(child: Text('営業日はありません'));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final todayDate = DateTime(_today.year, _today.month, _today.day);

    List<MapEntry<int, DateTime>> indexedDays = businessDays
        .asMap()
        .entries
        .toList();
    List<MapEntry<int, DateTime>> filteredDays = indexedDays.where((e) {
      final dateKey = DateTime(e.value.year, e.value.month, e.value.day);
      final config = _holidayConfigs[dateKey];
      switch (_dayFilter) {
        case DayFilter.withEvent:
          return config != null && config.tasks.isNotEmpty;
        case DayFilter.holiday:
          return config != null && config.isHoliday;
        case DayFilter.all:
          return true;
      }
    }).toList();

    int todayIndex = filteredDays.indexWhere((e) {
      final dayDate = DateTime(e.value.year, e.value.month, e.value.day);
      return dayDate.isAtSameMomentAs(todayDate) || dayDate.isAfter(todayDate);
    });
    if (todayIndex == -1) todayIndex = 0;

    // 表示している「月」が変わったか、初期移動が必要な場合のみ自動スクロールを実行するUX改善
    final currentMonthKey = DateTime(_focusedDay.year, _focusedDay.month);
    if (_needsScrollToToday || _lastScrolledMonth != currentMonthKey) {
      _needsScrollToToday = false;
      _lastScrolledMonth = currentMonthKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && filteredDays.isNotEmpty) {
          double offset = todayIndex * 98.0;
          // 最大スクロール範囲を超えないように制限
          if (offset > _scrollController.position.maxScrollExtent) {
            offset = _scrollController.position.maxScrollExtent;
          }
          _scrollController.jumpTo(offset);
        }
      });
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              _buildFilterChip('すべて', DayFilter.all),
              const SizedBox(width: 8),
              _buildFilterChip('予定ありのみ', DayFilter.withEvent),
              const SizedBox(width: 8),
              _buildFilterChip('休日のみ', DayFilter.holiday),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filteredDays.isEmpty
              ? const Center(
                  child: Text(
                    '条件に合う予定はありません',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  itemCount: filteredDays.length,
                  itemBuilder: (context, listIndex) {
                    final entry = filteredDays[listIndex];
                    final int index = entry.key;
                    DateTime day = entry.value;
                    bool isToday = isSameDay(day, _today);
                    final dateKey = DateTime(day.year, day.month, day.day);
                    final config = _holidayConfigs[dateKey];

                    return Dismissible(
                      key: ValueKey(
                        '${dateKey.toIso8601String()}_${config != null && (config.tasks.isNotEmpty || config.memo.isNotEmpty)}',
                      ),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (direction) async {
                        if (config == null ||
                            (config.tasks.isEmpty && config.memo.isEmpty)) {
                          return false;
                        }
                        return true;
                      },
                      onDismissed: (direction) {
                        final removedConfig = config;
                        setState(() => _holidayConfigs.remove(dateKey));
                        _saveData();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${day.month}/${day.day} の予定をクリアしました',
                            ),
                            action: SnackBarAction(
                              label: '元に戻す',
                              onPressed: () {
                                if (removedConfig != null) {
                                  setState(
                                    () => _holidayConfigs[dateKey] =
                                        removedConfig,
                                  );
                                  _saveData();
                                }
                              },
                            ),
                          ),
                        );
                      },
                      background: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.only(right: 20),
                        alignment: Alignment.centerRight,
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.delete_sweep,
                          color: Colors.white,
                        ),
                      ),
                      child: GestureDetector(
                        onTap: () => _showViewModal(context, day, config),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isToday
                                ? Theme.of(context).colorScheme.primaryContainer
                                      .withOpacity(0.3)
                                : Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(
                                  isDark ? 0.3 : 0.04,
                                ),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(
                              color: isToday
                                  ? Colors.blueAccent.withOpacity(0.5)
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: IntrinsicHeight(
                            child: Row(
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '第${index + 1}営業日',
                                      style: TextStyle(
                                        color: Colors.blueGrey[300],
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      '${day.month}/${day.day}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                    Text(
                                      [
                                        '',
                                        '月',
                                        '火',
                                        '水',
                                        '木',
                                        '金',
                                        '土',
                                        '日',
                                      ][day.weekday],
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blueGrey[600],
                                      ),
                                    ),
                                  ],
                                ),
                                const VerticalDivider(
                                  width: 24,
                                  thickness: 1,
                                  indent: 4,
                                  endIndent: 4,
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (config != null &&
                                          config.tasks.isNotEmpty)
                                        ...config.tasks.asMap().entries.map((
                                          taskEntry,
                                        ) {
                                          final t = taskEntry.value;
                                          return GestureDetector(
                                            onTap: () {
                                              setState(() => t.done = !t.done);
                                              _saveData();
                                            },
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  t.done
                                                      ? Icons.check_box_rounded
                                                      : Icons
                                                            .check_box_outline_blank_rounded,
                                                  size: 16,
                                                  color: t.done
                                                      ? Colors.green
                                                      : Colors.blueGrey,
                                                ),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    t.text,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      decoration: t.done
                                                          ? TextDecoration
                                                                .lineThrough
                                                          : null,
                                                      color: t.done
                                                          ? Colors.grey
                                                          : null,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        })
                                      else
                                        Text(
                                          'タスクなし',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey[400],
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      if (config != null &&
                                          config.memo.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 6,
                                          ),
                                          child: Text(
                                            config.memo,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.blueGrey[400],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (isToday)
                                  const Icon(
                                    Icons.push_pin,
                                    size: 16,
                                    color: Colors.blueAccent,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, DayFilter value) {
    final bool selected = _dayFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _dayFilter = value;
          _needsScrollToToday = true;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.blueGrey,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      // 左右の余白を 20 から 12 に少し狭めてスペースを確保
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 左側：年月切り替え部分を Expanded で囲み、はみ出しを防止
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(
                    () => _focusedDay = DateTime(
                      _focusedDay.year,
                      _focusedDay.month - 1,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 万が一画面幅が狭くても文字が潰れないようFlexibleで保護
                Flexible(
                  child: Text(
                    '${_focusedDay.year}/${_focusedDay.month}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(
                    () => _focusedDay = DateTime(
                      _focusedDay.year,
                      _focusedDay.month + 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 右側：アクションボタン（ここは元のサイズを維持）
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.search_rounded, size: 24),
                tooltip: '検索',
                onPressed: () async {
                  final DateTime? jumpTo = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SearchScreen(
                        holidayConfigs: _holidayConfigs,
                        milestones: _milestones,
                      ),
                    ),
                  );
                  if (jumpTo != null) {
                    setState(() {
                      _focusedDay = DateTime(jumpTo.year, jumpTo.month);
                      _needsScrollToToday = true;
                    });
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.today_rounded, size: 22),
                tooltip: '今日に戻る',
                onPressed: () => setState(() {
                  _focusedDay = DateTime.now();
                  _needsScrollToToday = true;
                }),
              ),
              IconButton(
                icon: Icon(
                  _isTimelineMode
                      ? Icons
                            .calendar_month_rounded // タイムライン中は「カレンダーアイコン」
                      : Icons.format_list_bulleted_rounded, // カレンダー中は「リストアイコン」
                  size: 24,
                ),
                tooltip: _isTimelineMode ? 'カレンダー表示' : 'タイムライン表示',
                onPressed: () {
                  setState(() {
                    _isTimelineMode = !_isTimelineMode;
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.settings_rounded, size: 26),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SettingsScreen(
                        includeWeekends: _includeWeekends,
                        fixedHolidays: _fixedHolidays,
                        onChanged: (newInclude, newFixed) {
                          setState(() {
                            _includeWeekends = newInclude;
                            _fixedHolidays = newFixed;
                          });
                          _saveData();
                        },
                      ),
                    ),
                  );
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineView() {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    final int differenceToSunday = _timelineBaseDate.weekday == 7
        ? 0
        : _timelineBaseDate.weekday;
    final DateTime sundayOfThisWeek = _timelineBaseDate.subtract(
      Duration(days: differenceToSunday),
    );

    final List<DateTime> sortedDates = List.generate(
      7,
      (index) => sundayOfThisWeek.add(Duration(days: index)),
    );

    // タイムラインの1時間あたりの高さ（ピクセル）
    const double hourHeight = 50.0;
    const int startTimelineHour = 7;
    const int endTimelineHour = 23;
    const int totalHours = endTimelineHour - startTimelineHour;
    const double timelineHeight = totalHours * hourHeight;

    // 左側の時間軸を表示する幅
    const double timeColumnWidth = 45.0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
                onPressed: () {
                  setState(() {
                    _timelineBaseDate = _timelineBaseDate.subtract(
                      const Duration(days: 7),
                    );
                  });
                },
              ),
              Text(
                '${_timelineBaseDate.month}/${_timelineBaseDate.day} 〜 ${sortedDates.last.month}/${sortedDates.last.day}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 20),
                onPressed: () {
                  setState(() {
                    _timelineBaseDate = _timelineBaseDate.add(
                      const Duration(days: 7),
                    );
                  });
                },
              ),
            ],
          ),
        ),

        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
          ),
          child: Row(
            children: [
              const SizedBox(width: timeColumnWidth),
              ...sortedDates.map((date) {
                final weekdayStr = [
                  '日',
                  '月',
                  '火',
                  '水',
                  '木',
                  '金',
                  '土',
                ][date.weekday % 7];
                final isToday = isSameDay(date, today);

                return Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${date.month}/${date.day}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isToday
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isToday ? Colors.blue : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: isToday
                            ? const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              )
                            : null,
                        child: Text(
                          weekdayStr,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isToday
                                ? Colors.white
                                : (date.weekday == 6
                                      ? Colors.blue
                                      : (date.weekday == 7
                                            ? Colors.red
                                            : Colors.black87)),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),

        Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.grey.withOpacity(0.15)),
              bottom: BorderSide(
                color: Colors.grey.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            color: Colors.grey.withOpacity(0.02),
          ),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左端の時間軸スペース（「終日」という文字を薄く置く）
              const SizedBox(
                width: timeColumnWidth,
                child: Center(
                  child: Text(
                    '終日',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              // 各曜日の終日イベントを横並びで配置
              ...sortedDates.map((date) {
                final dateKey = DateTime(date.year, date.month, date.day);
                final config = _holidayConfigs[dateKey];
                // 終日のタスクだけを抽出
                List<TaskItem> allDayTasks =
                    config?.tasks.where((t) => t.isAllDay).toList() ?? [];

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: allDayTasks.asMap().entries.map((taskEntry) {
                        int taskIndex = taskEntry.key;
                        var task = taskEntry.value;

                        return GestureDetector(
                          onTap: () {
                            _showEditTaskModal(
                              context,
                              date,
                              task,
                              taskIndex,
                              () {
                                setState(() {});
                              },
                            );
                          },
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: task.done
                                  ? Colors.grey.withOpacity(0.3)
                                  : Colors.blueGrey.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border(
                                left: BorderSide(
                                  color: task.done
                                      ? Colors.grey
                                      : Colors.blueGrey[400]!,
                                  width: 2.5,
                                ),
                              ),
                            ),
                            child: Text(
                              task.text,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                decoration: task.done
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: task.done ? Colors.grey : Colors.black87,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            child: SizedBox(
              height: timelineHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左端：縦に並ぶ時間軸
                  SizedBox(
                    width: timeColumnWidth,
                    child: Stack(
                      children: [
                        for (int i = 0; i <= totalHours; i++)
                          Positioned(
                            top: i * hourHeight - 6,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Text(
                                '${startTimelineHour + i}:00',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // 右側：各曜日のタイムラインエリア
                  Expanded(
                    child: Stack(
                      children: [
                        // 背景の横目盛り線
                        for (int i = 0; i <= totalHours; i++)
                          Positioned(
                            top: i * hourHeight,
                            left: 0,
                            right: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: Colors.grey.withOpacity(0.15),
                                    width: 0.8,
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // 7日分の列
                        Row(
                          children: sortedDates.asMap().entries.map((
                            dateEntry,
                          ) {
                            int dayIndex = dateEntry.key;
                            DateTime date = dateEntry.value;

                            final dateKey = DateTime(
                              date.year,
                              date.month,
                              date.day,
                            );
                            final config = _holidayConfigs[dateKey];
                            // 💡 ここでは「時間指定がある予定（終日ではない）」のみを抽出して描画
                            List<TaskItem> timedTasks =
                                config?.tasks
                                    .where((t) => !t.isAllDay)
                                    .toList() ??
                                [];

                            return Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    right: BorderSide(
                                      color: Colors.grey.withOpacity(0.1),
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                                child: Stack(
                                  children: timedTasks.asMap().entries.map((
                                    taskEntry,
                                  ) {
                                    int taskIndex = taskEntry.key;
                                    var task = taskEntry.value;

                                    double startDecimal =
                                        task.startHour +
                                        (task.startMinute / 60.0);
                                    double endDecimal =
                                        task.endHour + (task.endMinute / 60.0);

                                    if (startDecimal < startTimelineHour)
                                      startDecimal = startTimelineHour
                                          .toDouble();
                                    if (endDecimal > endTimelineHour)
                                      endDecimal = endTimelineHour.toDouble();

                                    double topPosition =
                                        (startDecimal - startTimelineHour) *
                                        hourHeight;
                                    double blockHeight =
                                        (endDecimal - startDecimal) *
                                        hourHeight;
                                    if (blockHeight <= 0)
                                      blockHeight = hourHeight * 0.5;

                                    final color = task.startHour < 12
                                        ? Colors.orange
                                        : Colors.blue;

                                    return Positioned(
                                      top: topPosition + 2,
                                      left: 2.0 + (taskIndex * 2),
                                      right: 2.0,
                                      height: blockHeight - 4,
                                      child: GestureDetector(
                                        onTap: () {
                                          _showEditTaskModal(
                                            context,
                                            date,
                                            task,
                                            taskIndex,
                                            () {
                                              setState(() {});
                                            },
                                          );
                                        },
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: task.done
                                                ? Colors.grey.withOpacity(0.2)
                                                : color.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border(
                                              left: BorderSide(
                                                color: task.done
                                                    ? Colors.grey
                                                    : color[600]!,
                                                width: 3,
                                              ),
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  task.text,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    decoration: task.done
                                                        ? TextDecoration
                                                              .lineThrough
                                                        : null,
                                                    color: task.done
                                                        ? Colors.grey
                                                        : Colors.black87,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                '${task.startHour}:${task.startMinute.toString().padLeft(2, '0')}',
                                                style: TextStyle(
                                                  fontSize: 8,
                                                  color: task.done
                                                      ? Colors.grey
                                                      : Colors.black54,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  int _currentPageIndex = 0;
  Widget _buildTopCards(int count, DateTime lastBD) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: 220,
        child: PageView(
          controller: _pageController,
          onPageChanged: (index) => setState(() => _currentPageIndex = index),
          children: [
            _buildBaseCard(
              title: '残り営業日',
              child: _buildCountContent(
                '',
                '$count',
                '最終営業日: ${lastBD.month}/${lastBD.day}',
                Colors.blueAccent,
              ),
            ),
            ..._milestones.asMap().entries.map((entry) {
              int index = entry.key;
              var milestone = entry.value;
              DateTime targetDate = milestone['isRecurring'] == true
                  ? _adjustToBusinessDay(
                      DateTime(
                        _focusedDay.year,
                        _focusedDay.month,
                        milestone['date'].day,
                      ),
                    )
                  : milestone['date'];
              final diff =
                  DateTime(targetDate.year, targetDate.month, targetDate.day)
                      .difference(
                        DateTime(_today.year, _today.month, _today.day),
                      )
                      .inDays;
              Color cardColor = _milestoneCardColor(milestone);
              return _buildBaseCard(
                title: milestone['title'],
                headerColor: cardColor,
                onLongPress: () => _showEditMilestoneModal(index),
                onDelete: () async {
                  await _cancelNotification(milestone['id']);
                  setState(() => _milestones.removeAt(index));
                  _saveMilestones();
                },
                child: _buildCountContent(
                  milestone['title'],
                  diff == 0 ? '当日' : '${diff.abs()}',
                  diff == 0
                      ? '本日の予定です'
                      : (diff > 0
                            ? '設定期限日: ${targetDate.month}/${targetDate.day}'
                            : '${diff.abs()} 日経過'),
                  cardColor,
                ),
              );
            }),
            _buildAddCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildCountContent(
    String title,
    String mainText,
    String subText,
    Color color,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          mainText,
          style: TextStyle(
            fontSize: 54,
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: -2,
          ),
        ),
        Text(
          subText,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildAddCard() {
    return GestureDetector(
      onTap: _showAddMilestoneModal,
      child: _buildBaseCard(
        title: '重要日を追加',
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, size: 48, color: Colors.blueAccent),
            Text(
              '重要日を追加',
              style: TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBaseCard({
    required String title,
    required Widget child,
    Color headerColor = Colors.blueAccent,
    VoidCallback? onLongPress,
    VoidCallback? onDelete,
    VoidCallback? onEdit,
  }) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.05,
              ),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              height: 32,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: headerColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (onEdit != null)
                    GestureDetector(
                      onTap: onEdit,
                      child: const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Icon(Icons.edit, color: Colors.white, size: 16),
                      ),
                    ),
                  if (onDelete != null)
                    GestureDetector(
                      onTap: onDelete,
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: Center(child: child)),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarCard(DateTime lastBD) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    DateTime? activeCardDate;
    Color activeColor = Colors.blueAccent;
    if (_currentPageIndex > 0 && _currentPageIndex <= _milestones.length) {
      var m = _milestones[_currentPageIndex - 1];
      activeCardDate = m['isRecurring'] == true
          ? _adjustToBusinessDay(
              DateTime(_focusedDay.year, _focusedDay.month, m['date'].day),
            )
          : m['date'];
      activeColor = _milestoneCardColor(m);
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: TableCalendar(
        // 2026年固定から、現在のシステム日付に合わせた動的レンジにUX改善
        calendarFormat: _calendarFormat, // 現在のフォーマットを適用
        onFormatChanged: (format) {
          setState(() {
            _calendarFormat = format; // 手動でスワイプ等された場合も状態を同期
          });
        },
        firstDay: DateTime(DateTime.now().year - 1, 1, 1),
        lastDay: DateTime(DateTime.now().year + 5, 12, 31),
        rowHeight: 45,
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
        ),
        focusedDay: _focusedDay,
        currentDay: _today,
        headerVisible: false,
        onPageChanged: (focusedDay) => setState(() => _focusedDay = focusedDay),
        selectedDayPredicate: (day) => isSameDay(day, activeCardDate ?? lastBD),
        onDaySelected: (selectedDay, focusedDay) =>
            _showDetailModal(context, selectedDay),
        calendarBuilders: CalendarBuilders(
          prioritizedBuilder: (context, day, focusedDay) {
            if (day.month != focusedDay.month) return const SizedBox.shrink();
            final dateKey = DateTime(day.year, day.month, day.day);
            final config = _holidayConfigs[dateKey];
            final bool isSelected = isSameDay(day, activeCardDate ?? lastBD);
            final bool isToday = isSameDay(day, _today);

            BoxDecoration? cellDecoration;
            TextStyle textStyle = TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color,
              fontSize: 14,
            );

            if (isSelected) {
              cellDecoration = BoxDecoration(
                color: activeCardDate != null ? activeColor : Colors.blueAccent,
                shape: BoxShape.circle,
              );
              textStyle = const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              );
            } else if (isToday) {
              cellDecoration = BoxDecoration(
                color: Colors.blue.withOpacity(isDark ? 0.3 : 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.blueAccent),
              );
              textStyle = const TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
              );
            } else if (_isRedLetterHoliday(day)) {
              textStyle = TextStyle(
                color: isDark ? Colors.redAccent[100] : Colors.redAccent,
                fontWeight: FontWeight.bold,
              );
            } else if (day.weekday == DateTime.saturday) {
              textStyle = TextStyle(
                color: isDark ? Colors.lightBlueAccent : Colors.blueAccent,
                fontWeight: FontWeight.bold,
              );
            } else if (day.weekday == DateTime.sunday || _isOffDay(day)) {
              textStyle = TextStyle(
                color: isDark ? Colors.redAccent[100] : Colors.redAccent,
              );
            }

            final bool hasEvent = config != null && config.tasks.isNotEmpty;
            final Color markerColor = (config?.isHoliday ?? false)
                ? Colors.redAccent
                : Theme.of(context).colorScheme.primary;

            return SizedBox(
              width: 38,
              height: 38,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (cellDecoration != null)
                    Container(
                      width: 34,
                      height: 34,
                      decoration: cellDecoration,
                    ),
                  Text('${day.day}', style: textStyle),
                  if (hasEvent)
                    Positioned(
                      bottom: 2,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : markerColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showViewModal(
    BuildContext context,
    DateTime selectedDay,
    HolidayData? config,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.only(
            left: 24,
            right: 24,
            top: 16,
            bottom: 32,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${selectedDay.month}/${selectedDay.day} の予定',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (config?.isHoliday == true)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '休日',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'タスク',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (config != null && config.tasks.isNotEmpty)
                        ...config.tasks.map(
                          (task) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  task.done
                                      ? Icons.check_box_rounded
                                      : Icons.check_box_outline_blank_rounded,
                                  size: 16,
                                  color: task.done
                                      ? Colors.green
                                      : Colors.blueGrey,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    task.text,
                                    style: TextStyle(
                                      fontSize: 14,
                                      decoration: task.done
                                          ? TextDecoration.lineThrough
                                          : null,
                                      color: task.done ? Colors.grey : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Text(
                          'タスクなし',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[400],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      const SizedBox(height: 16),
                      const Text(
                        'メモ',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (config != null && config.memo.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white10
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SelectableText(
                            config.memo,
                            style: const TextStyle(fontSize: 14, height: 1.6),
                          ),
                        )
                      else
                        Text(
                          'メモなし',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[400],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('編集する'),
                  onPressed: () {
                    Navigator.pop(context);
                    _showDetailModal(context, selectedDay);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetailModal(BuildContext context, DateTime selectedDay) {
    final dateKey = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day,
    );
    _holidayConfigs.putIfAbsent(dateKey, () => HolidayData());
    final config = _holidayConfigs[dateKey]!;
    final memoController = TextEditingController(text: config.memo);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${selectedDay.month}/${selectedDay.day} の詳細設定',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    FilterChip(
                      label: const Text('休日設定'),
                      selected: config.isHoliday,
                      selectedColor: Colors.redAccent.withOpacity(0.2),
                      checkmarkColor: Colors.redAccent,
                      labelStyle: TextStyle(
                        color: config.isHoliday ? Colors.redAccent : null,
                        fontWeight: config.isHoliday ? FontWeight.bold : null,
                      ),
                      onSelected: (bool selected) {
                        setModalState(() => config.isHoliday = selected);
                        setState(() {});
                        _saveData();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.blue.withOpacity(0.1),
                      foregroundColor: Colors.blue[800],
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: const Text(
                      '新しい予定を追加',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      // これを押した時に、時間設定ができる別モーダルを開く
                      _showAddTaskModal(context, selectedDay, () {
                        // 追加し終わったら、この一覧画面のUIも更新する
                        setModalState(() {});
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),

                const Text(
                  '登録済みの予定',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                if (config.tasks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      '予定はありません',
                      style: TextStyle(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                else
                  ...config.tasks.asMap().entries.map((entry) {
                    int index = entry.key;
                    var task = entry.value;

                    String timeLabel = "終日";
                    if (!task.isAllDay) {
                      final sh = task.startHour.toString().padLeft(2, '0');
                      final sm = task.startMinute.toString().padLeft(2, '0');
                      final eh = task.endHour.toString().padLeft(2, '0');
                      final em = task.endMinute.toString().padLeft(2, '0');
                      timeLabel = "$sh:$sm - $eh:$em";
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        // 1. 左端：タップで完了/未完了を切り替えるチェックボックス（Todo機能）
                        leading: IconButton(
                          icon: Icon(
                            task.done
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: task.done ? Colors.green : Colors.grey,
                          ),
                          onPressed: () {
                            setModalState(() {
                              task.done = !task.done;
                            });
                            setState(() {});
                            _saveData();
                          },
                        ),
                        // 2. 中央：予定の内容（タップすると編集モーダルを開く）
                        title: Text(
                          task.text,
                          style: TextStyle(
                            decoration: task.done
                                ? TextDecoration.lineThrough
                                : null,
                            color: task.done ? Colors.grey : null,
                          ),
                        ),
                        subtitle: Text(
                          timeLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: task.done ? Colors.grey : Colors.blue[700],
                          ),
                        ),
                        onTap: () {
                          // 予定をタップしたら編集用のモーダルを開く
                          _showEditTaskModal(
                            context,
                            selectedDay,
                            task,
                            index,
                            () {
                              setModalState(() {});
                            },
                          );
                        },
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          onPressed: () {
                            setModalState(() => config.tasks.removeAt(index));
                            setState(() {});
                            _saveData();
                          },
                        ),
                      ),
                    );
                  }),

                const SizedBox(height: 16),
                const Text(
                  'メモ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: memoController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: '自由にメモを入力（自動保存）',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (text) {
                    config.memo = text;
                    setState(() {});
                    _saveData();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddTaskModal(
    BuildContext context,
    DateTime date,
    VoidCallback onAdded,
  ) {
    final controller = TextEditingController();
    bool isAllDay = true;
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 18, minute: 0);
    bool hasError = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '予定の新規追加',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'タイトル',
                  hintText: '予定のタイトルを入力',
                  errorText: hasError ? 'タイトルを入力してください' : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (text) {
                  if (hasError && text.isNotEmpty) {
                    setModalState(() => hasError = false);
                  }
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('終日イベント'),
                value: isAllDay,
                activeColor: Colors.blue,
                onChanged: (v) => setModalState(() => isAllDay = v),
              ),
              if (!isAllDay)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Column(
                    children: [
                      // 開始時間のスワイプ選択
                      Row(
                        children: [
                          const SizedBox(
                            width: 12,
                            child: Text(
                              '開始',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SizedBox(
                              height: 80, // ドラムロールの高さ
                              child: CupertinoDatePicker(
                                mode: CupertinoDatePickerMode.time,
                                use24hFormat: true,
                                minuteInterval: 30, // 💡 30分単位に制限
                                initialDateTime: DateTime(
                                  2000,
                                  1,
                                  1,
                                  startTime.hour,
                                  startTime.minute,
                                ),
                                onDateTimeChanged: (DateTime newDateTime) {
                                  setModalState(() {
                                    startTime = TimeOfDay(
                                      hour: newDateTime.hour,
                                      minute: newDateTime.minute,
                                    );
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      // 終了時間のスワイプ選択
                      Row(
                        children: [
                          const SizedBox(
                            width: 12,
                            child: Text(
                              '終了',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SizedBox(
                              height: 80,
                              child: CupertinoDatePicker(
                                mode: CupertinoDatePickerMode.time,
                                use24hFormat: true,
                                minuteInterval: 30, // 💡 30分単位に制限
                                initialDateTime: DateTime(
                                  2000,
                                  1,
                                  1,
                                  endTime.hour,
                                  endTime.minute,
                                ),
                                onDateTimeChanged: (DateTime newDateTime) {
                                  setModalState(() {
                                    endTime = TimeOfDay(
                                      hour: newDateTime.hour,
                                      minute: newDateTime.minute,
                                    );
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('キャンセル'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      if (controller.text.trim().isEmpty) {
                        setModalState(() => hasError = true);
                        return;
                      }

                      setState(() {
                        final newTask = TaskItem(
                          text: controller.text.trim(),
                          done: false,
                          isAllDay: isAllDay,
                          startHour: startTime.hour,
                          startMinute: startTime.minute,
                          endHour: endTime.hour,
                          endMinute: endTime.minute,
                        );

                        final dateKey = DateTime(
                          date.year,
                          date.month,
                          date.day,
                        );
                        _holidayConfigs[dateKey]!.tasks.add(newTask);
                      });

                      _saveData();
                      onAdded(); // 親モーダルのUIを再描画する
                      Navigator.pop(context); // この入力モーダルを閉じる
                    },
                    child: const Text('追加'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditTaskModal(
    BuildContext context,
    DateTime date,
    TaskItem task,
    int index,
    VoidCallback onUpdated,
  ) {
    final controller = TextEditingController(text: task.text);
    bool isAllDay = task.isAllDay;
    TimeOfDay startTime = TimeOfDay(
      hour: task.startHour,
      minute: task.startMinute,
    );
    TimeOfDay endTime = TimeOfDay(hour: task.endHour, minute: task.endMinute);
    bool hasError = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '予定の編集',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'タイトル',
                  errorText: hasError ? 'タイトルを入力してください' : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (text) {
                  if (hasError && text.isNotEmpty) {
                    setModalState(() => hasError = false);
                  }
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('終日イベント'),
                value: isAllDay,
                activeColor: Colors.blue,
                onChanged: (v) => setModalState(() => isAllDay = v),
              ),
              if (!isAllDay)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Column(
                    children: [
                      // 開始時間のスワイプ選択
                      Row(
                        children: [
                          const SizedBox(
                            width: 12,
                            child: Text(
                              '開始',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SizedBox(
                              height: 80,
                              child: CupertinoDatePicker(
                                mode: CupertinoDatePickerMode.time,
                                use24hFormat: true,
                                minuteInterval: 30,
                                initialDateTime: DateTime(
                                  2000,
                                  1,
                                  1,
                                  startTime.hour,
                                  startTime.minute,
                                ),
                                onDateTimeChanged: (DateTime newDateTime) {
                                  setModalState(() {
                                    startTime = TimeOfDay(
                                      hour: newDateTime.hour,
                                      minute: newDateTime.minute,
                                    );
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      // 終了時間のスワイプ選択
                      Row(
                        children: [
                          const SizedBox(
                            width: 12,
                            child: Text(
                              '終了',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SizedBox(
                              height: 80,
                              child: CupertinoDatePicker(
                                mode: CupertinoDatePickerMode.time,
                                use24hFormat: true,
                                minuteInterval: 30,
                                initialDateTime: DateTime(
                                  2000,
                                  1,
                                  1,
                                  endTime.hour,
                                  endTime.minute,
                                ),
                                onDateTimeChanged: (DateTime newDateTime) {
                                  setModalState(() {
                                    endTime = TimeOfDay(
                                      hour: newDateTime.hour,
                                      minute: newDateTime.minute,
                                    );
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('キャンセル'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      if (controller.text.trim().isEmpty) {
                        setModalState(() => hasError = true);
                        return;
                      }

                      setState(() {
                        // 対象のタスクのデータを直接書き換える
                        task.text = controller.text.trim();
                        task.isAllDay = isAllDay;
                        task.startHour = startTime.hour;
                        task.startMinute = startTime.minute;
                        task.endHour = endTime.hour;
                        task.endMinute = endTime.minute;
                      });

                      _saveData();
                      onUpdated(); // 詳細モーダルのUIを更新
                      Navigator.pop(context); // 編集モーダルを閉じる
                    },
                    child: const Text('変更を保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemoInput({
    required TextEditingController controller,
    required Function(String) onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white10
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        minLines: 3,
        maxLines: 8,
        decoration: const InputDecoration(
          prefixIcon: Padding(
            padding: EdgeInsets.only(bottom: 60),
            child: Icon(Icons.notes, size: 20),
          ),
          hintText: 'メモを入力（自由記入）',
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        ),
        onChanged: onChanged,
      ),
    );
  }

  Color _milestoneCardColor(Map<String, dynamic> milestone) {
    if (milestone['colorValue'] != null) {
      return Color(milestone['colorValue']);
    }
    final DateTime targetDate = milestone['isRecurring'] == true
        ? _adjustToBusinessDay(
            DateTime(
              _focusedDay.year,
              _focusedDay.month,
              milestone['date'].day,
            ),
          )
        : milestone['date'];
    final diff = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    ).difference(DateTime(_today.year, _today.month, _today.day)).inDays;
    if (diff == 0) return Colors.redAccent;
    return diff > 0 ? Colors.orangeAccent : Colors.grey;
  }

  DateTime _adjustToBusinessDay(DateTime date) {
    DateTime adjusted = date;
    while (adjusted.weekday == DateTime.saturday ||
        adjusted.weekday == DateTime.sunday ||
        _isRedLetterHoliday(adjusted)) {
      adjusted = adjusted.subtract(const Duration(days: 1));
    }
    return adjusted;
  }

  static const List<Color> _milestoneColorPalette = [
    Colors.redAccent,
    Colors.orangeAccent,
    Colors.amber,
    Colors.green,
    Colors.teal,
    Colors.blueAccent,
    Colors.indigo,
    Colors.purpleAccent,
    Colors.pink,
    Colors.grey,
  ];

  Widget _buildColorPicker({
    required int? selectedValue,
    required void Function(int?) onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'カードの色',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                GestureDetector(
                  onTap: () => onSelected(null),
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [
                          Colors.redAccent,
                          Colors.orangeAccent,
                          Colors.grey,
                        ],
                      ),
                      border: Border.all(
                        color: selectedValue == null
                            ? Colors.black
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: selectedValue == null
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                ),
                ..._milestoneColorPalette.map((c) {
                  final bool isSelected = selectedValue == c.value;
                  return GestureDetector(
                    onTap: () => onSelected(c.value),
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.black : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddMilestoneModal() {
    _milestoneTitleController.clear();
    DateTime tempDate = DateTime(DateTime.now().year, DateTime.now().month, 25);
    bool isRecurring = false;
    bool isNotify = false;
    int? tempColorValue;
    bool hasError = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _milestoneTitleController,
                decoration: InputDecoration(
                  labelText: "タイトル",
                  errorText: hasError ? "タイトルを入力してください" : null, // ← 未入力時に表示
                ),
                onChanged: (text) {
                  // 入力されたらリアルタイムにエラーを消す親切設計
                  if (hasError && text.isNotEmpty) {
                    setModalState(() => hasError = false);
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.calendar_today,
                  color: Colors.blueGrey,
                ),
                title: Text(
                  "${tempDate.year}年${tempDate.month}月${tempDate.day}日",
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: const Text("タップして日付を変更"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: tempDate,
                    firstDate: DateTime(DateTime.now().year - 5),
                    lastDate: DateTime(DateTime.now().year + 10),
                    locale: const Locale('ja', 'JP'), // ← 日本語化
                    // ↓ カレンダーのデザインをモダンにカスタマイズ
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: Theme.of(context).colorScheme.copyWith(
                            // 選択された日付の背景色をテーマカラーに連動
                            primary: Theme.of(context).colorScheme.primary,
                            // ダイアログ内の文字色などを最適化
                            onPrimary: Theme.of(context).colorScheme.onPrimary,
                            surface: Theme.of(context).cardColor,
                          ),
                          // ダイアログの角を丸くしてモダンに
                          dialogTheme: DialogThemeData(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null) {
                    setModalState(() {
                      tempDate = picked;
                    });
                  }
                },
              ),
              SwitchListTile(
                title: const Text("毎月繰り返す"),
                value: isRecurring,
                onChanged: (v) => setModalState(() => isRecurring = v),
              ),
              SwitchListTile(
                title: const Text("当日の9時に通知"),
                value: isNotify,
                onChanged: (v) => setModalState(() => isNotify = v),
              ),
              _buildColorPicker(
                selectedValue: tempColorValue,
                onSelected: (v) => setModalState(() => tempColorValue = v),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (_milestoneTitleController.text.trim().isEmpty) {
                    setModalState(() => hasError = true);
                    return;
                  }
                  final int uniqueId =
                      DateTime.now().millisecondsSinceEpoch.hashCode;
                  final targetDate = isRecurring
                      ? tempDate
                      : _adjustToBusinessDay(tempDate);

                  final newMilestone = {
                    'id': uniqueId,
                    'title': _milestoneTitleController.text,
                    'date': targetDate,
                    'isRecurring': isRecurring,
                    'isNotify': isNotify,
                    'colorValue': tempColorValue,
                  };

                  setState(() => _milestones.add(newMilestone));
                  _saveMilestones();

                  if (isNotify) {
                    await _scheduleNotification(
                      uniqueId,
                      _milestoneTitleController.text,
                      targetDate,
                    );
                  }
                  Navigator.pop(context);
                },
                child: const Text("追加"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditMilestoneModal(int index) {
    var milestone = _milestones[index];
    _milestoneTitleController.text = milestone['title'];
    DateTime tempDate = milestone['date'];
    bool isRecurring = milestone['isRecurring'] ?? false;
    bool isNotify = milestone['isNotify'] ?? false;
    int? tempColorValue = milestone['colorValue'];
    final int uniqueId =
        milestone['id'] ?? DateTime.now().millisecondsSinceEpoch.hashCode;
    bool hasError = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _milestoneTitleController,
                decoration: InputDecoration(
                  labelText: "タイトル",
                  errorText: hasError ? "タイトルを入力してください" : null, // ← 未入力時に表示
                ),
                onChanged: (text) {
                  if (hasError && text.isNotEmpty) {
                    setModalState(() => hasError = false);
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.calendar_today,
                  color: Colors.blueGrey,
                ),
                title: Text(
                  "${tempDate.year}年${tempDate.month}月${tempDate.day}日",
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: const Text("タップして日付を変更"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: tempDate,
                    firstDate: DateTime(DateTime.now().year - 5),
                    lastDate: DateTime(DateTime.now().year + 10),
                    locale: const Locale('ja', 'JP'), // ← 日本語化
                    // ↓ カレンダーのデザインをモダンにカスタマイズ
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: Theme.of(context).colorScheme.copyWith(
                            primary: Theme.of(context).colorScheme.primary,
                            onPrimary: Theme.of(context).colorScheme.onPrimary,
                            surface: Theme.of(context).cardColor,
                          ),
                          dialogTheme: DialogThemeData(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null) {
                    setModalState(() {
                      tempDate = picked;
                    });
                  }
                },
              ),
              SwitchListTile(
                title: const Text("毎月繰り返す"),
                value: isRecurring,
                onChanged: (v) => setModalState(() => isRecurring = v),
              ),
              SwitchListTile(
                title: const Text("当日の9時に通知"),
                value: isNotify,
                onChanged: (v) => setModalState(() => isNotify = v),
              ),
              _buildColorPicker(
                selectedValue: tempColorValue,
                onSelected: (v) => setModalState(() => tempColorValue = v),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (_milestoneTitleController.text.trim().isEmpty) {
                    setModalState(() => hasError = true);
                    return;
                  }
                  await _cancelNotification(uniqueId);
                  final targetDate = isRecurring
                      ? tempDate
                      : _adjustToBusinessDay(tempDate);

                  setState(() {
                    _milestones[index] = {
                      'id': uniqueId,
                      'title': _milestoneTitleController.text,
                      'date': targetDate,
                      'isRecurring': isRecurring,
                      'isNotify': isNotify,
                      'colorValue': tempColorValue,
                    };
                  });
                  _saveMilestones();

                  if (isNotify) {
                    await _scheduleNotification(
                      uniqueId,
                      _milestoneTitleController.text,
                      targetDate,
                    );
                    Navigator.pop(context);
                  }
                },
                child: const Text("保存"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- 以下、元の高機能ロジックを復元統合・安全化した別画面クラス ---

class SearchScreen extends StatefulWidget {
  final Map<DateTime, HolidayData> holidayConfigs;
  final List<Map<String, dynamic>> milestones;

  const SearchScreen({
    super.key,
    required this.holidayConfigs,
    required this.milestones,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> milestoneResults = [];
    if (_query.isNotEmpty) {
      milestoneResults = widget.milestones.where((m) {
        final title = m['title'] ?? '';
        return title.toString().toLowerCase().contains(_query.toLowerCase());
      }).toList();
    }

    List<MapEntry<DateTime, HolidayData>> dayResults = [];
    if (_query.isNotEmpty) {
      widget.holidayConfigs.forEach((key, value) {
        bool matchTask = value.tasks.any(
          (t) => t.text.toLowerCase().contains(_query.toLowerCase()),
        );
        bool matchMemo = value.memo.toLowerCase().contains(
          _query.toLowerCase(),
        );
        if (matchTask || matchMemo) {
          dayResults.add(MapEntry(key, value));
        }
      });
      dayResults.sort((a, b) => a.key.compareTo(b.key));
    }

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '予定やメモを検索...',
            border: InputBorder.none,
          ),
          onChanged: (val) => setState(() => _query = val),
        ),
      ),
      body: _query.isEmpty
          ? const Center(child: Text('キーワードを入力してください'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (milestoneResults.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '重要日',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  ...milestoneResults.map(
                    (m) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.star, color: Colors.amber),
                        title: Text(m['title']),
                        subtitle: Text(
                          '${m['date'].year}/${m['date'].month}/${m['date'].day}',
                        ),
                        onTap: () => Navigator.pop(context, m['date']),
                      ),
                    ),
                  ),
                ],
                if (dayResults.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '予定・メモ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  ...dayResults.map(
                    (e) => Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.event_note,
                          color: Colors.blueAccent,
                        ),
                        title: Text('${e.key.month}/${e.key.day}'),
                        subtitle: Text(
                          e.value.tasks.isNotEmpty
                              ? e.value.tasks.map((t) => t.text).join('、')
                              : e.value.memo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.pop(context, e.key),
                      ),
                    ),
                  ),
                ],
                if (milestoneResults.isEmpty && dayResults.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Text(
                        '該当する項目が見つかりません',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final bool includeWeekends;
  final List<FixedHoliday> fixedHolidays;
  final Function(bool, List<FixedHoliday>) onChanged;

  const SettingsScreen({
    super.key,
    required this.includeWeekends,
    required this.fixedHolidays,
    required this.onChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _tempIncludeWeekends;
  late List<FixedHoliday> _tempFixedHolidays;

  @override
  void initState() {
    super.initState();
    _tempIncludeWeekends = widget.includeWeekends;
    _tempFixedHolidays = List.from(widget.fixedHolidays);
  }

  Future<void> _exportData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> exportMap = {};
      exportMap['holiday_configs'] = prefs.getString('holiday_configs') ?? '{}';
      exportMap['include_weekends'] =
          prefs.getBool('include_weekends') ?? false;
      exportMap['fixed_holidays_v2'] =
          prefs.getStringList('fixed_holidays_v2') ?? [];
      exportMap['saved_milestones'] =
          prefs.getString('saved_milestones') ?? '[]';
      exportMap['theme_mode'] = prefs.getInt('theme_mode') ?? 0;
      exportMap['theme_color'] =
          prefs.getInt('theme_color') ?? Colors.blueAccent.value;

      String jsonStr = jsonEncode(exportMap);
      await Clipboard.setData(ClipboardData(text: jsonStr));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('バックアップデータをクリップボードにコピーしました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('エクスポートに失敗しました')));
    }
  }

  Future<void> _importData() async {
    try {
      ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data == null || data.text == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('クリップボードが空です')));
        return;
      }

      Map<String, dynamic> importMap = jsonDecode(data.text!);
      final prefs = await SharedPreferences.getInstance();

      if (importMap.containsKey('holiday_configs')) {
        await prefs.setString('holiday_configs', importMap['holiday_configs']);
      }
      if (importMap.containsKey('include_weekends')) {
        await prefs.setBool('include_weekends', importMap['include_weekends']);
      }
      if (importMap.containsKey('fixed_holidays_v2')) {
        List<String> fixedList = List<String>.from(
          importMap['fixed_holidays_v2'],
        );
        await prefs.setStringList('fixed_holidays_v2', fixedList);
      }
      if (importMap.containsKey('saved_milestones')) {
        await prefs.setString(
          'saved_milestones',
          importMap['saved_milestones'],
        );
      }
      if (importMap.containsKey('theme_mode')) {
        await prefs.setInt('theme_mode', importMap['theme_mode']);
      }
      if (importMap.containsKey('theme_color')) {
        await prefs.setInt('theme_color', importMap['theme_color']);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('データを復元しました。アプリを再起動して反映してください')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('復元に失敗しました。正しいデータ形式か確認してください')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('土日を営業日に含める'),
                  subtitle: const Text('カレンダー上でのカウント対象になります'),
                  value: _tempIncludeWeekends,
                  onChanged: (val) {
                    setState(() => _tempIncludeWeekends = val);
                    widget.onChanged(_tempIncludeWeekends, _tempFixedHolidays);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              '外観設定',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('テーマカラー変更'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...[
                        Colors.blueAccent,
                        Colors.teal,
                        Colors.deepPurple,
                        Colors.orange,
                      ].map(
                        (c) => GestureDetector(
                          onTap: () async {
                            themeColorNotifier.value = c;
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setInt('theme_color', c.value);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(left: 6),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: const Text('ダークモード設定'),
                  trailing: DropdownButton<ThemeMode>(
                    value: themeModeNotifier.value,
                    onChanged: (ThemeMode? newMode) async {
                      if (newMode != null) {
                        themeModeNotifier.value = newMode;
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setInt('theme_mode', newMode.index);
                        setState(() {});
                      }
                    },
                    items: const [
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text('システム連動'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text('ライト'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text('ダーク'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              'データ管理（バックアップ）',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.copy_all, color: Colors.blueAccent),
                  title: const Text('データをエクスポート'),
                  subtitle: const Text('設定や予定の全データをコピーします'),
                  onTap: _exportData,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.restart_alt,
                    color: Colors.orangeAccent,
                  ),
                  title: const Text('データをインポート（復元）'),
                  subtitle: const Text('クリップボードからデータを読み込みます'),
                  onTap: _importData,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
