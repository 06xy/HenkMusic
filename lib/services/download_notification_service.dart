import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class DownloadNotificationService {
  static const _channelId = 'music_downloads';
  static const _channelName = '歌曲下载';
  static const _notificationId = 3001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();
    _initialized = true;
  }

  Future<void> showProgress({
    required String title,
    required String body,
    required int completed,
    required int total,
  }) async {
    await init();
    final safeTotal = total <= 0 ? 1 : total;
    final safeCompleted = completed.clamp(0, safeTotal);
    final details = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '显示酷狗歌曲下载进度',
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: safeTotal,
      progress: safeCompleted,
      ongoing: safeCompleted < safeTotal,
      autoCancel: safeCompleted >= safeTotal,
      importance: Importance.low,
      priority: Priority.low,
    );
    await _plugin.show(
      _notificationId,
      title,
      body,
      NotificationDetails(android: details),
    );
  }

  Future<void> showDone(String title, String body) async {
    await init();
    const details = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '显示酷狗歌曲下载进度',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    await _plugin.show(
      _notificationId,
      title,
      body,
      const NotificationDetails(android: details),
    );
  }
}
