import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart';
import 'services/music_service.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/user_page.dart';

final musicService = MusicService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await AudioService.init(
    builder: () => musicService.audioHandler,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.music_player.playback',
      androidNotificationChannelName: '音乐播放',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: true,
    ),
  );
  await musicService.init();
  runApp(const MusicPlayerApp());
}

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HenkMusic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.light,
      home: const HomePage(),
      routes: {
        '/settings': (context) => const SettingsPage(),
        '/user': (context) => const UserPage(),
      },
    );
  }
}
