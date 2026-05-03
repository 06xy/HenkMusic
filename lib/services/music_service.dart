import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:charset/charset.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import '../models/song.dart';
import 'download_notification_service.dart';
import 'kugou_api_service.dart';

class KugouDownloadProgress {
  final String playlistId;
  final String title;
  final int total;
  final int completed;
  final int skipped;
  final int failed;
  final String current;
  final bool running;

  const KugouDownloadProgress({
    required this.playlistId,
    required this.title,
    required this.total,
    required this.completed,
    required this.skipped,
    required this.failed,
    required this.current,
    required this.running,
  });

  double get ratio => total <= 0 ? 0 : completed / total;

  KugouDownloadProgress copyWith({
    int? total,
    int? completed,
    int? skipped,
    int? failed,
    String? current,
    bool? running,
  }) {
    return KugouDownloadProgress(
      playlistId: playlistId,
      title: title,
      total: total ?? this.total,
      completed: completed ?? this.completed,
      skipped: skipped ?? this.skipped,
      failed: failed ?? this.failed,
      current: current ?? this.current,
      running: running ?? this.running,
    );
  }
}

class LyricWord {
  final String text;
  final Duration begin;
  final Duration end;

  const LyricWord({required this.text, required this.begin, required this.end});

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'beginMs': begin.inMilliseconds,
      'endMs': end.inMilliseconds,
    };
  }

  factory LyricWord.fromJson(Map<String, dynamic> json) {
    return LyricWord(
      text: json['text'] as String? ?? '',
      begin: Duration(milliseconds: json['beginMs'] as int? ?? 0),
      end: Duration(milliseconds: json['endMs'] as int? ?? 0),
    );
  }
}

class LyricLine {
  final Duration time;
  final String text;
  final List<LyricWord> words;

  const LyricLine({
    required this.time,
    required this.text,
    this.words = const [],
  });

  bool get hasWordTiming => words.any((word) => word.text.trim().isNotEmpty);

  MapEntry<Duration, String> toEntry() => MapEntry(time, text);

  Map<String, dynamic> toJson() {
    return {
      'timeMs': time.inMilliseconds,
      'text': text,
      'words': words.map((word) => word.toJson()).toList(),
    };
  }

  factory LyricLine.fromJson(Map<String, dynamic> json) {
    return LyricLine(
      time: Duration(milliseconds: json['timeMs'] as int? ?? 0),
      text: json['text'] as String? ?? '',
      words:
          (json['words'] as List<dynamic>?)
              ?.whereType<Map>()
              .map(
                (item) => LyricWord.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList() ??
          const [],
    );
  }
}

class MusicService extends ChangeNotifier with WidgetsBindingObserver {
  static const _ttmlMetadataNs = 'http://www.w3.org/ns/ttml#metadata';
  static const _prefRootDir = 'music_root_dir';
  static const _prefMusicSource = 'music_source';
  static const _prefCurrentSong = 'current_song_idx';
  static const _prefCurrentPos = 'current_position_ms';
  static const _prefPlayMode = 'play_mode';
  static const _prefIsPlaying = 'is_playing';
  static const _prefBoundaryAction = 'boundary_action';
  static const _prefAutoScanInterval = 'auto_scan_interval';
  static const _prefLastScanAt = 'last_scan_at_ms';
  static const _prefSongLibrary = 'song_library_json';
  static const _prefKugouSongs = 'kugou_song_library_json';
  static const _prefKugouCookies = 'kugou_cookies_json';
  static const _prefKugouUser = 'kugou_user_json';
  static const _prefKugouPlaylistName = 'kugou_playlist_name';
  static const _prefLyricsCache = 'lyrics_cache_json';
  static const _prefTtmlLyricsCache = 'ttml_lyrics_cache_json';
  static const _prefExperimentalTtmlLyrics = 'experimental_ttml_lyrics';

  final ja.AudioPlayer _audioPlayer = ja.AudioPlayer();
  final KugouApiService _kugouApi = KugouApiService();
  final DownloadNotificationService _downloadNotifications =
      DownloadNotificationService();
  final _random = Random();
  late final MusicAudioHandler audioHandler;

  String? _rootDir;
  MusicSource _musicSource = MusicSource.local;
  List<Song> _songs = [];
  List<Song> _kugouSongs = [];
  final Set<String> _loadingKugouLyrics = {};
  KugouUser? _kugouUser;
  List<KugouPlaylist> _kugouPlaylists = [];
  String? _kugouPlaylistName;
  bool _kugouLoading = false;
  String? _kugouError;
  KugouDownloadProgress? _kugouDownloadProgress;
  Map<String, List<MapEntry<Duration, String>>> _lyricsCache = {};
  Map<String, List<LyricLine>> _ttmlLyricsCache = {};
  int _scannedCount = 0;
  String? _lastError;
  int _scannedLyricsCount = 0;
  int _failedLyricsCount = 0;
  DateTime? _lastScanAt;

  Duration _currentPosition = Duration.zero;
  int _currentSongIndex = 0;
  PlayMode _playMode = PlayMode.sequential;
  BoundaryAction _boundaryAction = BoundaryAction.keepPlaying;
  AutoScanInterval _autoScanInterval = AutoScanInterval.off;
  bool _experimentalTtmlLyrics = false;
  bool _isPlaying = false;
  bool _sourceLoaded = false;
  bool _scanning = false;
  bool _loadingDurations = false;
  bool _libraryLoaded = false;
  Timer? _saveTimer;
  DateTime _lastPositionNotify = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription? _durationSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _currentIndexSub;
  StreamSubscription? _stateSub;

  MusicService() {
    audioHandler = MusicAudioHandler(this);
  }

  String? get rootDir => _rootDir;
  List<Song> get songs => _songs;
  MusicSource get musicSource => _musicSource;
  KugouUser? get kugouUser => _kugouUser;
  List<KugouPlaylist> get kugouPlaylists => _kugouPlaylists;
  String? get kugouPlaylistName => _kugouPlaylistName;
  bool get kugouLoading => _kugouLoading;
  String? get kugouError => _kugouError;
  KugouDownloadProgress? get kugouDownloadProgress => _kugouDownloadProgress;
  bool get isKugouLoggedIn => _kugouApi.cookies['token']?.isNotEmpty == true;
  bool get isDemo => _songs.isEmpty;
  int get scannedCount => _scannedCount;
  String? get lastError => _lastError;
  int get scannedLyricsCount => _scannedLyricsCount;
  int get failedLyricsCount => _failedLyricsCount;
  DateTime? get lastScanAt => _lastScanAt;
  bool get scanning => _scanning;
  bool get loadingDurations => _loadingDurations;
  bool get libraryLoaded => _libraryLoaded;

  Duration get currentPosition => _currentPosition;
  int get currentSongIndex => _currentSongIndex;
  PlayMode get playMode => _playMode;
  BoundaryAction get boundaryAction => _boundaryAction;
  AutoScanInterval get autoScanInterval => _autoScanInterval;
  bool get experimentalTtmlLyrics => _experimentalTtmlLyrics;
  bool get isPlaying => _isPlaying;

  List<Song> get activeSongs {
    if (_musicSource == MusicSource.kugou) return _kugouSongs;
    return _songs.isEmpty && _rootDir == null ? demoSongs : _songs;
  }

  Song get currentSong {
    if (activeSongs.isEmpty) {
      return const Song(title: '暂无歌曲', artist: '', duration: Duration.zero);
    }
    return activeSongs[_currentSongIndex.clamp(0, activeSongs.length - 1)];
  }

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    await _downloadNotifications.init();
    _bindPlayer();
    final prefs = await SharedPreferences.getInstance();
    _rootDir = prefs.getString(_prefRootDir);
    _musicSource =
        MusicSource.values[(prefs.getInt(_prefMusicSource) ?? 0).clamp(
          0,
          MusicSource.values.length - 1,
        )];
    _restoreKugouFromPrefs(prefs);
    _restoreLibraryFromPrefs(prefs);
    _currentSongIndex = prefs.getInt(_prefCurrentSong) ?? 0;
    _currentPosition = Duration(
      milliseconds: prefs.getInt(_prefCurrentPos) ?? 0,
    );
    _playMode =
        PlayMode.values[(prefs.getInt(_prefPlayMode) ?? 0).clamp(
          0,
          PlayMode.values.length - 1,
        )];
    _boundaryAction =
        BoundaryAction.values[(prefs.getInt(_prefBoundaryAction) ?? 1).clamp(
          0,
          BoundaryAction.values.length - 1,
        )];
    _autoScanInterval =
        AutoScanInterval.values[(prefs.getInt(_prefAutoScanInterval) ?? 0)
            .clamp(0, AutoScanInterval.values.length - 1)];
    _experimentalTtmlLyrics =
        prefs.getBool(_prefExperimentalTtmlLyrics) ?? false;
    final lastScanMs = prefs.getInt(_prefLastScanAt);
    _lastScanAt = lastScanMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lastScanMs);
    _isPlaying = false;

    _libraryLoaded = true;
    _clampCurrentIndex();
    _publishSystemQueue();
    _publishSystemState();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_savePlaybackState());
    }
  }

  void _bindPlayer() {
    _durationSub = _audioPlayer.durationStream.listen((duration) {
      if (duration != null) {
        _updateCurrentSongDuration(duration);
        _publishSystemQueue();
        _publishSystemState();
        notifyListeners();
      }
    });
    _positionSub = _audioPlayer.positionStream.listen((position) {
      _currentPosition = position;
      final now = DateTime.now();
      if (now.difference(_lastPositionNotify).inMilliseconds >= 80) {
        _lastPositionNotify = now;
        _publishSystemState();
        notifyListeners();
      }
    });
    _currentIndexSub = _audioPlayer.currentIndexStream.listen((index) {
      if (_musicSource == MusicSource.kugou) return;
      if (index == null || index == _currentSongIndex) return;
      _currentSongIndex = index.clamp(0, activeSongs.length - 1);
      _currentPosition = _audioPlayer.position;
      unawaited(_savePlaybackState());
      _publishSystemState();
      notifyListeners();
    });
    _stateSub = _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ja.ProcessingState.completed) {
        unawaited(next(fromUser: false));
      }
      final playing = state.playing;
      if (_isPlaying != playing) {
        _isPlaying = playing;
        _syncSaveTimer();
        _savePlaybackState();
        _publishSystemState();
        notifyListeners();
      }
    });
  }

  Future<void> setRootDir(String path) async {
    _rootDir = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefRootDir, path);
    await _savePlaybackState();
    notifyListeners();
  }

  Future<void> setMusicSource(MusicSource source) async {
    if (_musicSource == source) return;
    _musicSource = source;
    _currentSongIndex = 0;
    _currentPosition = Duration.zero;
    _sourceLoaded = false;
    await _audioPlayer.stop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefMusicSource, source.index);
    await _savePlaybackState();
    _clampCurrentIndex();
    _publishSystemQueue();
    _publishSystemState();
    notifyListeners();
  }

  Future<void> sendKugouCaptcha(String mobile) async {
    _kugouLoading = true;
    _kugouError = null;
    notifyListeners();
    try {
      await _kugouApi.sendCaptcha(mobile);
      await _persistKugouState();
    } catch (e) {
      _kugouError = e.toString();
      rethrow;
    } finally {
      _kugouLoading = false;
      notifyListeners();
    }
  }

  Future<void> loginKugou(String mobile, String code) async {
    _kugouLoading = true;
    _kugouError = null;
    notifyListeners();
    try {
      _kugouUser = await _kugouApi.loginByCaptcha(mobile: mobile, code: code);
      _kugouPlaylists = await _kugouApi.fetchPlaylists();
      await _persistKugouState();
    } catch (e) {
      _kugouError = e.toString();
      rethrow;
    } finally {
      _kugouLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshKugouProfile() async {
    if (!isKugouLoggedIn) return;
    _kugouLoading = true;
    _kugouError = null;
    notifyListeners();
    try {
      _kugouUser = await _kugouApi.fetchUserDetail();
      _kugouPlaylists = await _kugouApi.fetchPlaylists();
      await _persistKugouState();
    } catch (e) {
      _kugouError = e.toString();
    } finally {
      _kugouLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadKugouPlaylist(KugouPlaylist playlist) async {
    _kugouLoading = true;
    _kugouError = null;
    notifyListeners();
    try {
      _kugouSongs = await _kugouApi.fetchPlaylistSongsFor(playlist);
      _kugouPlaylistName = playlist.name;
      _musicSource = MusicSource.kugou;
      _currentSongIndex = 0;
      _currentPosition = Duration.zero;
      _sourceLoaded = false;
      await _audioPlayer.stop();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefMusicSource, MusicSource.kugou.index);
      await _persistKugouState();
      _publishSystemQueue();
      _publishSystemState();
    } catch (e) {
      _kugouError = e.toString();
      rethrow;
    } finally {
      _kugouLoading = false;
      notifyListeners();
    }
  }

  Future<Directory> downloadCurrentKugouSong() async {
    if (_rootDir == null) throw Exception('请先在设置中选择本地音乐根目录');
    final song = currentSong;
    if (song.source != MusicSource.kugou) throw Exception('当前歌曲不是酷狗在线歌曲');
    await _downloadKugouSongAssets(song);
    await scanFiles();
    return Directory(_rootDir!);
  }

  Future<void> downloadKugouPlaylist(KugouPlaylist playlist) async {
    if (_rootDir == null) throw Exception('请先在设置中选择本地音乐根目录');
    final existing = _kugouDownloadProgress;
    if (existing?.running == true) throw Exception('已有歌单正在下载');

    final songs = await _kugouApi.fetchPlaylistSongsFor(playlist);
    _kugouDownloadProgress = KugouDownloadProgress(
      playlistId: playlist.id,
      title: playlist.name,
      total: songs.length,
      completed: 0,
      skipped: 0,
      failed: 0,
      current: songs.isEmpty ? '无歌曲' : '准备下载',
      running: true,
    );
    await _notifyDownloadProgress();
    notifyListeners();

    var completed = 0;
    var skipped = 0;
    var failed = 0;
    for (final song in songs) {
      _kugouDownloadProgress = _kugouDownloadProgress?.copyWith(
        completed: completed,
        skipped: skipped,
        failed: failed,
        current: song.title,
      );
      await _notifyDownloadProgress();
      notifyListeners();

      try {
        final result = await _downloadKugouSongAssets(song);
        if (result.skipped) skipped++;
      } catch (e) {
        failed++;
        debugPrint('[MusicService] Failed to download ${song.title}: $e');
        completed++;
        _kugouDownloadProgress = _kugouDownloadProgress?.copyWith(
          completed: completed,
          skipped: skipped,
          failed: failed,
          current: '已跳过：${song.title}',
        );
        await _notifyDownloadProgress();
        notifyListeners();
        continue;
      }
      completed++;
      _kugouDownloadProgress = _kugouDownloadProgress?.copyWith(
        completed: completed,
        skipped: skipped,
        failed: failed,
      );
      await _notifyDownloadProgress();
      notifyListeners();
    }

    _kugouDownloadProgress = _kugouDownloadProgress?.copyWith(
      completed: completed,
      skipped: skipped,
      failed: failed,
      current: '下载完成',
      running: false,
    );
    await _downloadNotifications.showDone(
      '歌单下载完成',
      '${playlist.name}：$completed/${songs.length} 首，跳过 $skipped，失败 $failed',
    );
    await scanFiles();
    notifyListeners();
  }

  Future<void> _notifyDownloadProgress() async {
    final progress = _kugouDownloadProgress;
    if (progress == null) return;
    try {
      await _downloadNotifications.showProgress(
        title: progress.running ? '正在下载歌单' : '歌单下载完成',
        body:
            '${progress.title} ${progress.completed}/${progress.total} ${progress.current}',
        completed: progress.completed,
        total: progress.total,
      );
    } catch (e) {
      debugPrint('[MusicService] Failed to update download notification: $e');
    }
  }

  Future<({bool skipped})> _downloadKugouSongAssets(Song song) async {
    final root = _rootDir;
    if (root == null) throw Exception('请先在设置中选择本地音乐根目录');
    final baseName = _safeFileName('${song.title}-${song.artist}');
    final musicDir = Directory(p.join(root, 'music'));
    final lyricsDir = Directory(p.join(root, 'lyrics'));
    final coverDir = Directory(p.join(root, 'cover'));
    await musicDir.create(recursive: true);
    await lyricsDir.create(recursive: true);
    await coverDir.create(recursive: true);

    final audioFile = File(p.join(musicDir.path, '$baseName.mp3'));
    final lyricFile = File(p.join(lyricsDir.path, '$baseName.lrc'));
    final coverFile = File(p.join(coverDir.path, '$baseName.png'));
    final alreadyComplete =
        await audioFile.exists() &&
        await lyricFile.exists() &&
        (song.coverUrl.isEmpty || await coverFile.exists());

    if (!await audioFile.exists()) {
      final url = await _kugouApi.resolveSongUrl(song);
      await _downloadUrlToFile(url, audioFile);
    }

    if (!await lyricFile.exists()) {
      final lyrics = await _kugouApi.fetchLyrics(song);
      if (lyrics.isNotEmpty) {
        await lyricFile.writeAsString(_formatLrc(lyrics), encoding: utf8);
      }
    }

    if (song.coverUrl.isNotEmpty && !await coverFile.exists()) {
      try {
        await _downloadUrlToFile(song.coverUrl, coverFile);
      } catch (e) {
        debugPrint('[MusicService] Failed to download cover: $e');
      }
    }

    final key = song.artist.isNotEmpty && song.artist != '未知歌手'
        ? '${song.title}-${song.artist}'
        : song.title;
    if (await lyricFile.exists()) {
      _lyricsCache[key] = parseLrc(await _readLyricFile(lyricFile));
      await _persistLibrary();
    }
    return (skipped: alreadyComplete);
  }

  Future<void> _downloadUrlToFile(String url, File target) async {
    final temp = File('${target.path}.download');
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('下载失败：HTTP ${response.statusCode}');
      }
      await response.pipe(temp.openWrite());
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
    } finally {
      client.close(force: true);
      if (await temp.exists()) {
        try {
          await temp.delete();
        } catch (_) {}
      }
    }
  }

  String _formatLrc(List<MapEntry<Duration, String>> lyrics) {
    return lyrics
        .map((line) {
          final duration = line.key;
          final minutes = duration.inMinutes
              .remainder(60)
              .toString()
              .padLeft(2, '0');
          final seconds = duration.inSeconds
              .remainder(60)
              .toString()
              .padLeft(2, '0');
          final centiseconds = (duration.inMilliseconds.remainder(1000) ~/ 10)
              .toString()
              .padLeft(2, '0');
          return '[$minutes:$seconds.$centiseconds]${line.value}';
        })
        .join('\n');
  }

  String _safeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<void> logoutKugou() async {
    _kugouApi.clearCookies();
    _kugouUser = null;
    _kugouPlaylists = [];
    _kugouSongs = [];
    _kugouPlaylistName = null;
    _sourceLoaded = false;
    if (_musicSource == MusicSource.kugou) {
      _musicSource = MusicSource.local;
      _currentSongIndex = 0;
      _currentPosition = Duration.zero;
      await _audioPlayer.stop();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKugouCookies);
    await prefs.remove(_prefKugouUser);
    await prefs.remove(_prefKugouSongs);
    await prefs.remove(_prefKugouPlaylistName);
    await prefs.setInt(_prefMusicSource, _musicSource.index);
    _publishSystemQueue();
    _publishSystemState();
    notifyListeners();
  }

  Future<void> clearRootDir() async {
    _rootDir = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefRootDir);
    await prefs.remove(_prefSongLibrary);
    await prefs.remove(_prefLyricsCache);
    await prefs.remove(_prefTtmlLyricsCache);
    await prefs.remove(_prefLastScanAt);
    _songs = [];
    _lyricsCache = {};
    _ttmlLyricsCache = {};
    _scannedCount = 0;
    _scannedLyricsCount = 0;
    _failedLyricsCount = 0;
    _lastError = null;
    _lastScanAt = null;
    _currentSongIndex = 0;
    _currentPosition = Duration.zero;
    _sourceLoaded = false;
    await _audioPlayer.stop();
    _publishSystemQueue();
    _publishSystemState();
    notifyListeners();
  }

  Future<void> _savePlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefCurrentSong, _currentSongIndex);
    await prefs.setInt(_prefCurrentPos, _currentPosition.inMilliseconds);
    await prefs.setInt(_prefPlayMode, _playMode.index);
    await prefs.setBool(_prefIsPlaying, _isPlaying);
    await prefs.setInt(_prefBoundaryAction, _boundaryAction.index);
  }

  void _restoreLibraryFromPrefs(SharedPreferences prefs) {
    final songJson = prefs.getString(_prefSongLibrary);
    if (songJson != null && songJson.isNotEmpty) {
      try {
        final items = jsonDecode(songJson) as List<dynamic>;
        _songs = items
            .whereType<Map>()
            .map((item) => Song.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        _scannedCount = _songs.length;
      } catch (e) {
        debugPrint('[MusicService] Failed to restore library: $e');
      }
    }

    final lyricsJson = prefs.getString(_prefLyricsCache);
    if (lyricsJson != null && lyricsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(lyricsJson) as Map<String, dynamic>;
        _lyricsCache = decoded.map((key, value) {
          final lines = (value as List<dynamic>).map((item) {
            final row = item as Map<String, dynamic>;
            return MapEntry(
              Duration(milliseconds: row['ms'] as int? ?? 0),
              row['text'] as String? ?? '',
            );
          }).toList();
          return MapEntry(key, lines);
        });
        _scannedLyricsCount = _lyricsCache.length;
      } catch (e) {
        debugPrint('[MusicService] Failed to restore lyrics cache: $e');
      }
    }

    final ttmlLyricsJson = prefs.getString(_prefTtmlLyricsCache);
    if (ttmlLyricsJson != null && ttmlLyricsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(ttmlLyricsJson) as Map<String, dynamic>;
        _ttmlLyricsCache = decoded.map((key, value) {
          final lines = (value as List<dynamic>)
              .whereType<Map>()
              .map(
                (item) => LyricLine.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList();
          return MapEntry(key, lines);
        });
      } catch (e) {
        debugPrint('[MusicService] Failed to restore TTML lyrics cache: $e');
      }
    }
  }

  void _restoreKugouFromPrefs(SharedPreferences prefs) {
    final cookieJson = prefs.getString(_prefKugouCookies);
    if (cookieJson != null && cookieJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(cookieJson) as Map<String, dynamic>;
        _kugouApi.restoreCookies(
          decoded.map((key, value) => MapEntry(key, value.toString())),
        );
      } catch (e) {
        debugPrint('[MusicService] Failed to restore Kugou cookies: $e');
      }
    }

    final userJson = prefs.getString(_prefKugouUser);
    if (userJson != null && userJson.isNotEmpty) {
      try {
        _kugouUser = KugouUser.fromJson(
          Map<String, dynamic>.from(jsonDecode(userJson) as Map),
        );
      } catch (e) {
        debugPrint('[MusicService] Failed to restore Kugou user: $e');
      }
    }

    final songJson = prefs.getString(_prefKugouSongs);
    if (songJson != null && songJson.isNotEmpty) {
      try {
        final items = jsonDecode(songJson) as List<dynamic>;
        _kugouSongs = items
            .whereType<Map>()
            .map((item) => Song.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      } catch (e) {
        debugPrint('[MusicService] Failed to restore Kugou songs: $e');
      }
    }

    _kugouPlaylistName = prefs.getString(_prefKugouPlaylistName);
  }

  Future<void> _persistLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefSongLibrary,
      jsonEncode(_songs.map((song) => song.toJson()).toList()),
    );
    final lyricsJson = _lyricsCache.map((key, value) {
      return MapEntry(
        key,
        value
            .map((line) => {'ms': line.key.inMilliseconds, 'text': line.value})
            .toList(),
      );
    });
    await prefs.setString(_prefLyricsCache, jsonEncode(lyricsJson));
    final ttmlLyricsJson = _ttmlLyricsCache.map((key, value) {
      return MapEntry(key, value.map((line) => line.toJson()).toList());
    });
    await prefs.setString(_prefTtmlLyricsCache, jsonEncode(ttmlLyricsJson));
    if (_lastScanAt != null) {
      await prefs.setInt(_prefLastScanAt, _lastScanAt!.millisecondsSinceEpoch);
    }
  }

  Future<void> _persistKugouState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKugouCookies, jsonEncode(_kugouApi.cookies));
    if (_kugouUser != null) {
      await prefs.setString(_prefKugouUser, jsonEncode(_kugouUser!.toJson()));
    }
    await prefs.setString(
      _prefKugouSongs,
      jsonEncode(_kugouSongs.map((song) => song.toJson()).toList()),
    );
    if (_kugouPlaylistName == null) {
      await prefs.remove(_prefKugouPlaylistName);
    } else {
      await prefs.setString(_prefKugouPlaylistName, _kugouPlaylistName!);
    }
  }

  void _syncSaveTimer() {
    _saveTimer?.cancel();
    if (_isPlaying) {
      _saveTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _savePlaybackState(),
      );
    }
  }

  Future<PlaybackActionResult> playSongAt(int index) async {
    if (activeSongs.isEmpty) return PlaybackActionResult.reachedBoundary;
    _currentSongIndex = index.clamp(0, activeSongs.length - 1);
    _currentPosition = Duration.zero;
    _sourceLoaded = false;
    _publishSystemState();
    await play();
    return PlaybackActionResult.played;
  }

  Future<PlaybackActionResult> playSong(Song song) async {
    final index = activeSongs.indexOf(song);
    if (index == -1) return PlaybackActionResult.reachedBoundary;
    return playSongAt(index);
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    final song = currentSong;
    if (song.source == MusicSource.local && song.filePath.isEmpty) {
      _isPlaying = true;
      _sourceLoaded = true;
      _syncSaveTimer();
      _publishSystemState();
      notifyListeners();
      return;
    }

    try {
      if (!_sourceLoaded) {
        await _loadPlaybackQueue(
          initialIndex: _currentSongIndex,
          initialPosition: _currentPosition,
        );
      } else if (song.source == MusicSource.kugou) {
        await _audioPlayer.seek(_currentPosition);
      } else {
        await _audioPlayer.seek(_currentPosition, index: _currentSongIndex);
      }
    } catch (e) {
      _lastError = '播放失败: $e';
      _isPlaying = false;
      _publishSystemState();
      notifyListeners();
      rethrow;
    }
    await _audioPlayer.play();
    if (song.source == MusicSource.kugou) {
      unawaited(_loadKugouLyrics(song));
    }
    _isPlaying = true;
    _syncSaveTimer();
    await _savePlaybackState();
    _publishSystemState();
    notifyListeners();
  }

  Future<void> pause() async {
    if (currentSong.filePath.isNotEmpty ||
        currentSong.source == MusicSource.kugou) {
      await _audioPlayer.pause();
    }
    _isPlaying = false;
    _syncSaveTimer();
    await _savePlaybackState();
    _publishSystemState();
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    final duration = currentSong.duration;
    final safePosition = duration > Duration.zero && position > duration
        ? duration
        : position;
    _currentPosition = safePosition < Duration.zero
        ? Duration.zero
        : safePosition;
    if ((currentSong.filePath.isNotEmpty ||
            currentSong.source == MusicSource.kugou) &&
        _sourceLoaded) {
      await _audioPlayer.seek(_currentPosition);
    }
    await _savePlaybackState();
    _publishSystemState();
    notifyListeners();
  }

  Future<PlaybackActionResult> next({bool fromUser = true}) async {
    if (activeSongs.isEmpty) return PlaybackActionResult.reachedBoundary;
    switch (_playMode) {
      case PlayMode.singleRepeat:
        await seek(Duration.zero);
        await play();
        return PlaybackActionResult.restartedCurrent;
      case PlayMode.shuffle:
        await playSongAt(_random.nextInt(activeSongs.length));
        return PlaybackActionResult.played;
      case PlayMode.sequential:
        if (_currentSongIndex >= activeSongs.length - 1) {
          return _handleBoundary(fromUser);
        }
        await playSongAt(_currentSongIndex + 1);
        return PlaybackActionResult.played;
    }
  }

  Future<PlaybackActionResult> previous({bool fromUser = true}) async {
    if (activeSongs.isEmpty) return PlaybackActionResult.reachedBoundary;
    switch (_playMode) {
      case PlayMode.singleRepeat:
        await seek(Duration.zero);
        await play();
        return PlaybackActionResult.restartedCurrent;
      case PlayMode.shuffle:
        await playSongAt(_random.nextInt(activeSongs.length));
        return PlaybackActionResult.played;
      case PlayMode.sequential:
        if (_currentSongIndex <= 0) {
          return _handleBoundary(fromUser);
        }
        await playSongAt(_currentSongIndex - 1);
        return PlaybackActionResult.played;
    }
  }

  Future<PlaybackActionResult> _handleBoundary(bool fromUser) async {
    if (_boundaryAction == BoundaryAction.restartCurrent) {
      await playSongAt(_currentSongIndex);
      return PlaybackActionResult.restartedCurrent;
    }
    if (!fromUser) {
      await pause();
      await seek(Duration.zero);
    }
    return PlaybackActionResult.reachedBoundary;
  }

  Future<void> cyclePlayMode() async {
    _playMode = PlayMode.values[(_playMode.index + 1) % PlayMode.values.length];
    await _applyPlaybackMode();
    await _savePlaybackState();
    _publishSystemState();
    notifyListeners();
  }

  Future<void> setBoundaryAction(BoundaryAction action) async {
    _boundaryAction = action;
    await _savePlaybackState();
    notifyListeners();
  }

  Future<void> setAutoScanInterval(AutoScanInterval interval) async {
    _autoScanInterval = interval;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefAutoScanInterval, interval.index);
    notifyListeners();
  }

  Future<void> setExperimentalTtmlLyrics(bool enabled) async {
    if (_experimentalTtmlLyrics == enabled) return;
    _experimentalTtmlLyrics = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefExperimentalTtmlLyrics, enabled);
    notifyListeners();
  }

  Future<void> scanFiles({bool isAutomatic = false}) async {
    if (_rootDir == null) return;
    if (_scanning) return;
    debugPrint(
      '[MusicService] ${isAutomatic ? 'Auto' : 'Manual'} scan started',
    );

    _scanning = true;
    _libraryLoaded = false;
    _lastError = null;
    notifyListeners();

    try {
      final rootPath = _rootDir!;
      final musicDir = Directory(p.join(rootPath, 'music'));
      final lyricsDir = Directory(p.join(rootPath, 'lyrics'));
      final ttmlDir = Directory(p.join(rootPath, 'ttml'));
      final coverDir = Directory(p.join(rootPath, 'cover'));
      final scannedSongs = <Song>[];
      final scannedLyrics = <String, List<MapEntry<Duration, String>>>{};
      final scannedTtmlLyrics = <String, List<LyricLine>>{};
      var scannedLyricsCount = 0;
      var failedLyricsCount = 0;

      final audioExts = {
        '.mp3',
        '.wav',
        '.flac',
        '.aac',
        '.ogg',
        '.wma',
        '.m4a',
      };

      Directory scanDir = musicDir;
      if (!await musicDir.exists()) {
        scanDir = Directory(rootPath);
      }

      if (await scanDir.exists()) {
        final entities = scanDir.listSync();
        final audioFiles = <File>[];
        for (final entity in entities) {
          if (entity is! File) continue;
          final ext = p.extension(entity.path).toLowerCase();
          if (audioExts.contains(ext)) {
            audioFiles.add(entity);
          }
        }

        audioFiles.sort((a, b) => a.path.compareTo(b.path));

        for (final file in audioFiles) {
          final nameWithoutExt = p.basenameWithoutExtension(file.path);
          String title;
          String artist;
          final splitIndex = nameWithoutExt.lastIndexOf('-');
          if (splitIndex > 0 && splitIndex < nameWithoutExt.length - 1) {
            title = nameWithoutExt.substring(0, splitIndex).trim();
            artist = nameWithoutExt.substring(splitIndex + 1).trim();
          } else {
            title = nameWithoutExt;
            artist = '未知歌手';
          }

          String coverPath = '';
          if (await coverDir.exists()) {
            final coverFile = File(
              p.join(coverDir.path, '$nameWithoutExt.png'),
            );
            if (await coverFile.exists()) {
              coverPath = coverFile.path;
            }
          }

          scannedSongs.add(
            Song(
              title: title,
              artist: artist,
              duration: Duration.zero,
              filePath: file.path,
              coverPath: coverPath,
            ),
          );
        }
      } else {
        _lastError = '目录不存在: ${scanDir.path}';
      }

      if (_experimentalTtmlLyrics && await ttmlDir.exists()) {
        final result = await _scanTtmlLyricsDir(
          ttmlDir,
          scannedLyrics,
          scannedTtmlLyrics,
        );
        scannedLyricsCount += result.success;
        failedLyricsCount += result.failed;
      }
      if (await lyricsDir.exists()) {
        final result = await _scanLrcLyricsDir(
          lyricsDir,
          scannedLyrics,
          preferExisting: _experimentalTtmlLyrics,
        );
        scannedLyricsCount += result.success;
        failedLyricsCount += result.failed;
      }
      if (await Directory(rootPath).exists()) {
        final result = await _scanLrcLyricsDir(
          Directory(rootPath),
          scannedLyrics,
          preferExisting: _experimentalTtmlLyrics,
        );
        scannedLyricsCount += result.success;
        failedLyricsCount += result.failed;
      }

      _songs = scannedSongs;
      _lyricsCache = scannedLyrics;
      _ttmlLyricsCache = scannedTtmlLyrics;
      _sourceLoaded = false;
      _scannedLyricsCount = scannedLyricsCount;
      _failedLyricsCount = failedLyricsCount;
      _scannedCount = _songs.length;
      _lastScanAt = DateTime.now();
      _clampCurrentIndex();
      debugPrint(
        '[MusicService] Scanned $_scannedCount songs, ${_lyricsCache.length} lyric files',
      );
      await _persistLibrary();
      _publishSystemQueue();
      _publishSystemState();
      unawaited(_loadDurationsInBackground());
    } catch (e, stack) {
      _lastError = '扫描出错: $e';
      debugPrint('[MusicService] EXCEPTION: $e\n$stack');
    }

    _scanning = false;
    _libraryLoaded = true;
    _publishSystemState();
    notifyListeners();
  }

  Future<({int success, int failed})> _scanLrcLyricsDir(
    Directory dir,
    Map<String, List<MapEntry<Duration, String>>> target, {
    required bool preferExisting,
  }) async {
    var success = 0;
    var failed = 0;
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      if (p.extension(entity.path).toLowerCase() != '.lrc') continue;
      final lrcName = p.basenameWithoutExtension(entity.path).trim();
      try {
        final content = await _readLyricFile(entity);
        if (!preferExisting || !target.containsKey(lrcName)) {
          target[lrcName] = parseLrc(content);
        }
        success++;
      } catch (e) {
        failed++;
        debugPrint('[MusicService] Failed to read lrc: ${entity.path} -> $e');
      }
    }
    return (success: success, failed: failed);
  }

  Future<({int success, int failed})> _scanTtmlLyricsDir(
    Directory dir,
    Map<String, List<MapEntry<Duration, String>>> target,
    Map<String, List<LyricLine>> richTarget,
  ) async {
    var success = 0;
    var failed = 0;
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      if (p.extension(entity.path).toLowerCase() != '.ttml') continue;
      final ttmlName = p.basenameWithoutExtension(entity.path).trim();
      try {
        final content = await _readLyricFile(entity);
        final lines = parseTtmlLines(content);
        richTarget[ttmlName] = lines;
        target[ttmlName] = lines.map((line) => line.toEntry()).toList();
        success++;
      } catch (e) {
        failed++;
        debugPrint('[MusicService] Failed to read ttml: ${entity.path} -> $e');
      }
    }
    return (success: success, failed: failed);
  }

  Future<String> _readLyricFile(File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3));
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return gbk.decode(bytes);
    }
  }

  Future<void> _loadDurationsInBackground() async {
    if (_songs.isEmpty || _loadingDurations) return;
    _loadingDurations = true;
    notifyListeners();

    final metadataPlayer = ja.AudioPlayer();
    try {
      for (var i = 0; i < _songs.length; i++) {
        final song = _songs[i];
        if (song.filePath.isEmpty || song.duration > Duration.zero) continue;
        try {
          final duration = await metadataPlayer.setFilePath(song.filePath);
          if (duration != null && duration > Duration.zero) {
            _songs[i] = song.copyWith(duration: duration);
            _publishSystemQueue();
            _publishSystemState();
            notifyListeners();
          }
        } catch (e) {
          debugPrint(
            '[MusicService] Failed to load duration: ${song.filePath} -> $e',
          );
        }
      }
    } finally {
      await metadataPlayer.dispose();
      await _persistLibrary();
      _loadingDurations = false;
      notifyListeners();
    }
  }

  List<MapEntry<Duration, String>> getLyrics(String songTitle, String artist) {
    final song = currentSong;
    if (song.source == MusicSource.kugou &&
        song.title == songTitle &&
        song.artist == artist) {
      final key = _lyricsKeyForSong(song);
      final cached = _lyricsCache[key];
      if (cached != null && cached.isNotEmpty) return cached;
      unawaited(_loadKugouLyrics(song));
      return [const MapEntry(Duration.zero, '歌词加载中')];
    }

    final fullName = artist.isNotEmpty && artist != '未知歌手'
        ? '$songTitle-$artist'
        : songTitle;
    return _lyricsCache[fullName] ??
        _lyricsCache['$artist-$songTitle'] ??
        _lyricsCache[songTitle] ??
        [const MapEntry(Duration.zero, '暂无歌词')];
  }

  List<LyricLine> getLyricLines(String songTitle, String artist) {
    final song = currentSong;
    if (song.source == MusicSource.kugou &&
        song.title == songTitle &&
        song.artist == artist) {
      return getLyrics(
        songTitle,
        artist,
      ).map((line) => LyricLine(time: line.key, text: line.value)).toList();
    }

    final fullName = artist.isNotEmpty && artist != '未知歌手'
        ? '$songTitle-$artist'
        : songTitle;
    if (_experimentalTtmlLyrics) {
      final ttmlLines =
          _ttmlLyricsCache[fullName] ??
          _ttmlLyricsCache['$artist-$songTitle'] ??
          _ttmlLyricsCache[songTitle];
      if (ttmlLines != null && ttmlLines.isNotEmpty) return ttmlLines;
    }

    return getLyrics(
      songTitle,
      artist,
    ).map((line) => LyricLine(time: line.key, text: line.value)).toList();
  }

  String _lyricsKeyForSong(Song song) {
    if (song.source == MusicSource.kugou && song.hash.isNotEmpty) {
      return 'kg:${song.hash}';
    }
    return song.artist.isNotEmpty && song.artist != '未知歌手'
        ? '${song.title}-${song.artist}'
        : song.title;
  }

  Future<void> _loadKugouLyrics(Song song) async {
    final key = _lyricsKeyForSong(song);
    if (_lyricsCache.containsKey(key) || _loadingKugouLyrics.contains(key)) {
      return;
    }
    _loadingKugouLyrics.add(key);
    try {
      final lyrics = await _kugouApi.fetchLyrics(song);
      if (lyrics.isNotEmpty) {
        _lyricsCache[key] = lyrics;
        await _persistLibrary();
      }
    } catch (e) {
      debugPrint('[MusicService] Failed to load Kugou lyrics: $e');
    } finally {
      _loadingKugouLyrics.remove(key);
      notifyListeners();
    }
  }

  void _clampCurrentIndex() {
    if (activeSongs.isEmpty) {
      _currentSongIndex = 0;
    } else {
      _currentSongIndex = _currentSongIndex.clamp(0, activeSongs.length - 1);
    }
  }

  void _updateCurrentSongDuration(Duration duration) {
    final target = _musicSource == MusicSource.kugou ? _kugouSongs : _songs;
    if (target.isEmpty ||
        _currentSongIndex < 0 ||
        _currentSongIndex >= target.length) {
      return;
    }
    if (_musicSource == MusicSource.kugou) {
      _kugouSongs[_currentSongIndex] = _kugouSongs[_currentSongIndex].copyWith(
        duration: duration,
      );
    } else {
      _songs[_currentSongIndex] = _songs[_currentSongIndex].copyWith(
        duration: duration,
      );
    }
  }

  Future<void> _loadPlaybackQueue({
    required int initialIndex,
    required Duration initialPosition,
  }) async {
    final songs = activeSongs;
    if (_musicSource == MusicSource.kugou) {
      final song = currentSong;
      final uri = await _uriForPlayback(song);
      if (uri == null) return;
      final loadedDuration = await _audioPlayer.setAudioSource(
        ja.AudioSource.uri(
          uri,
          tag: MediaItem(
            id: song.hash,
            title: song.title,
            artist: song.artist,
            album: song.album.isEmpty ? null : song.album,
            duration: song.duration > Duration.zero ? song.duration : null,
            artUri: _artUriForSong(song),
          ),
        ),
        initialPosition: initialPosition,
      );
      if (loadedDuration != null) {
        _updateCurrentSongDuration(loadedDuration);
      }
      await _applyPlaybackMode();
      _sourceLoaded = true;
      _publishSystemQueue();
      _publishSystemState();
      return;
    }

    final sources = <ja.AudioSource>[];
    for (var i = 0; i < songs.length; i++) {
      final song = songs[i];
      final uri = await _uriForPlayback(song);
      if (uri == null) continue;
      sources.add(
        ja.AudioSource.uri(
          uri,
          tag: MediaItem(
            id: song.source == MusicSource.kugou ? song.hash : song.filePath,
            title: song.title,
            artist: song.artist,
            album: song.album.isEmpty ? null : song.album,
            duration: song.duration > Duration.zero ? song.duration : null,
            artUri: _artUriForSong(song),
          ),
        ),
      );
    }
    if (sources.isEmpty) return;

    final safeIndex = initialIndex.clamp(0, sources.length - 1);
    final loadedDuration = await _audioPlayer.setAudioSources(
      sources,
      initialIndex: safeIndex,
      initialPosition: initialPosition,
    );
    if (loadedDuration != null) {
      _updateCurrentSongDuration(loadedDuration);
    }
    await _applyPlaybackMode();
    _sourceLoaded = true;
    _publishSystemQueue();
    _publishSystemState();
  }

  Future<Uri?> _uriForPlayback(Song song) async {
    if (song.source == MusicSource.kugou) {
      final url = await _kugouApi.resolveSongUrl(song);
      final index = _kugouSongs.indexOf(song);
      if (index >= 0 && _kugouSongs[index].playUrl != url) {
        _kugouSongs[index] = _kugouSongs[index].copyWith(playUrl: url);
        unawaited(_persistKugouState());
      }
      return Uri.parse(url);
    }
    if (song.filePath.isEmpty) return null;
    return Uri.file(song.filePath);
  }

  Future<void> _applyPlaybackMode() async {
    await _audioPlayer.setLoopMode(
      _playMode == PlayMode.singleRepeat ? ja.LoopMode.one : ja.LoopMode.off,
    );
    await _audioPlayer.setShuffleModeEnabled(_playMode == PlayMode.shuffle);
  }

  MediaItem _mediaItemForSong(Song song) {
    return MediaItem(
      id: song.source == MusicSource.kugou
          ? song.hash
          : song.filePath.isEmpty
          ? '${song.title}-${song.artist}'
          : song.filePath,
      title: song.title,
      artist: song.artist.isEmpty ? null : song.artist,
      album: song.album.isEmpty ? null : song.album,
      duration: song.duration > Duration.zero ? song.duration : null,
      artUri: _artUriForSong(song),
    );
  }

  Uri? _artUriForSong(Song song) {
    if (song.coverPath.isNotEmpty) return Uri.file(song.coverPath);
    if (song.coverUrl.isNotEmpty) return Uri.tryParse(song.coverUrl);
    return null;
  }

  void _publishSystemQueue() {
    final queueItems = activeSongs
        .where((song) => song.title.isNotEmpty && song.title != '暂无歌曲')
        .map(_mediaItemForSong)
        .toList();
    audioHandler.queue.add(queueItems);
  }

  void _publishSystemState() {
    final songs = activeSongs;
    final hasSong = songs.isNotEmpty && currentSong.title != '暂无歌曲';
    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      _isPlaying ? MediaControl.pause : MediaControl.play,
      MediaControl.skipToNext,
    ];

    if (hasSong) {
      audioHandler.mediaItem.add(_mediaItemForSong(currentSong));
    } else {
      audioHandler.mediaItem.add(null);
    }

    audioHandler.playbackState.add(
      PlaybackState(
        controls: controls,
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: const {MediaAction.seek},
        processingState: _mapProcessingState(_audioPlayer.processingState),
        playing: _isPlaying,
        updatePosition: _currentPosition,
        bufferedPosition: _audioPlayer.bufferedPosition,
        speed: _audioPlayer.speed,
        queueIndex: hasSong
            ? _currentSongIndex.clamp(0, songs.length - 1)
            : null,
      ),
    );
  }

  AudioProcessingState _mapProcessingState(ja.ProcessingState state) {
    return switch (state) {
      ja.ProcessingState.idle => AudioProcessingState.idle,
      ja.ProcessingState.loading => AudioProcessingState.loading,
      ja.ProcessingState.buffering => AudioProcessingState.buffering,
      ja.ProcessingState.ready => AudioProcessingState.ready,
      ja.ProcessingState.completed => AudioProcessingState.completed,
    };
  }

  static List<MapEntry<Duration, String>> parseLrc(String content) {
    final lines = content.split('\n');
    final result = <MapEntry<Duration, String>>[];
    final tagReg = RegExp(r'^\[(\d{2}):(\d{2})\.?(\d{0,3})\](.*)');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final match = tagReg.firstMatch(trimmed);
      if (match != null) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        final msStr = match.group(3) ?? '';
        final ms = msStr.isEmpty ? 0 : int.parse(msStr.padRight(3, '0'));
        final text = match.group(4) ?? '';
        result.add(
          MapEntry(
            Duration(minutes: min, seconds: sec, milliseconds: ms),
            text,
          ),
        );
      }
    }

    result.sort((a, b) => a.key.compareTo(b.key));
    return result;
  }

  static List<MapEntry<Duration, String>> parseTtml(String content) {
    return parseTtmlLines(content).map((line) => line.toEntry()).toList();
  }

  static List<LyricLine> parseTtmlLines(String content) {
    final lines = <LyricLine>[];
    final document = XmlDocument.parse(content);
    final paragraphs = document.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'p',
    );

    for (final paragraph in paragraphs) {
      final begin = _parseTtmlTime(paragraph.getAttribute('begin'));
      final dur = _parseTtmlTime(paragraph.getAttribute('dur'));
      final end = _parseTtmlTime(paragraph.getAttribute('end'));
      final start = begin ?? (end != null && dur != null ? end - dur : null);
      if (start == null || start < Duration.zero) continue;

      final parsedLine = _parseTtmlParagraph(paragraph, start);
      lines.add(parsedLine);
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  static LyricLine _parseTtmlParagraph(XmlElement paragraph, Duration start) {
    final lead = <LyricWord>[];
    final background = <LyricWord>[];

    for (final node in paragraph.children) {
      if (node is XmlText) {
        _appendTtmlTextNode(lead, node.value, start);
      } else if (node is XmlElement) {
        final role = node.getAttribute('role', namespace: _ttmlMetadataNs);
        if (role == 'x-bg') {
          _appendTtmlElementWords(background, node, start);
        } else {
          _appendTtmlElementWords(lead, node, start);
        }
      }
    }

    final words = [
      ...lead,
      if (lead.isNotEmpty && background.isNotEmpty)
        LyricWord(text: '\n', begin: start, end: start),
      ...background,
    ];
    final text = _normalizeTtmlText(words.map((word) => word.text).join());
    return LyricLine(time: start, text: text, words: words);
  }

  static void _appendTtmlElementWords(
    List<LyricWord> target,
    XmlElement element,
    Duration fallbackTime,
  ) {
    final begin = _parseTtmlTime(element.getAttribute('begin')) ?? fallbackTime;
    final end = _parseTtmlTime(element.getAttribute('end')) ?? begin;

    if (element.children.whereType<XmlElement>().isEmpty) {
      final text = _normalizeInlineTtmlText(element.innerText);
      if (text.isNotEmpty) {
        target.add(LyricWord(text: text, begin: begin, end: end));
      }
      return;
    }

    for (final child in element.children) {
      if (child is XmlText) {
        _appendTtmlTextNode(target, child.value, begin);
      } else if (child is XmlElement) {
        _appendTtmlElementWords(target, child, begin);
      }
    }
  }

  static void _appendTtmlTextNode(
    List<LyricWord> target,
    String text,
    Duration time,
  ) {
    final normalized = _normalizeInlineTtmlText(text);
    if (normalized.isEmpty) return;
    target.add(LyricWord(text: normalized, begin: time, end: time));
  }

  static String _normalizeTtmlText(String text) {
    return text
        .split(RegExp(r'\s*\n\s*'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  static String _normalizeInlineTtmlText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ');
  }

  static Duration? _parseTtmlTime(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    final clock = RegExp(
      r'^((\d+):)?(\d{1,2}):(\d{2})(?:[.,](\d{1,3}))?$',
    ).firstMatch(trimmed);
    if (clock != null) {
      final hours = int.tryParse(clock.group(2) ?? '0') ?? 0;
      final minutes = int.tryParse(clock.group(3) ?? '0') ?? 0;
      final seconds = int.tryParse(clock.group(4) ?? '0') ?? 0;
      final msStr = clock.group(5) ?? '';
      final milliseconds = msStr.isEmpty
          ? 0
          : int.parse(msStr.padRight(3, '0').substring(0, 3));
      return Duration(
        hours: hours,
        minutes: minutes,
        seconds: seconds,
        milliseconds: milliseconds,
      );
    }

    final offset = RegExp(r'^(\d+(?:\.\d+)?)(h|m|s|ms)$').firstMatch(trimmed);
    if (offset == null) return null;
    final amount = double.tryParse(offset.group(1) ?? '');
    if (amount == null) return null;
    return switch (offset.group(2)) {
      'h' => Duration(milliseconds: (amount * 3600000).round()),
      'm' => Duration(milliseconds: (amount * 60000).round()),
      's' => Duration(milliseconds: (amount * 1000).round()),
      'ms' => Duration(milliseconds: amount.round()),
      _ => null,
    };
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _durationSub?.cancel();
    _positionSub?.cancel();
    _currentIndexSub?.cancel();
    _stateSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }
}

class MusicAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  MusicAudioHandler(this._musicService);

  final MusicService _musicService;

  @override
  Future<void> play() => _musicService.play();

  @override
  Future<void> pause() => _musicService.pause();

  @override
  Future<void> seek(Duration position) => _musicService.seek(position);

  @override
  Future<void> skipToNext() => _musicService.next();

  @override
  Future<void> skipToPrevious() => _musicService.previous();

  @override
  Future<void> stop() => _musicService.pause();
}
