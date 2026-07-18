import 'dart:io';

import '../models/song.dart';

typedef KugouUrlResolver = Future<String> Function(Song song);
typedef LocalFileExists = Future<bool> Function(String path);

class PlaybackSourceException implements Exception {
  const PlaybackSourceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PlaybackSourceResolver {
  PlaybackSourceResolver({
    required KugouUrlResolver resolveKugouUrl,
    LocalFileExists? localFileExists,
  }) : _resolveKugouUrl = resolveKugouUrl,
       _localFileExists = localFileExists ?? _defaultLocalFileExists;

  final KugouUrlResolver _resolveKugouUrl;
  final LocalFileExists _localFileExists;

  Future<Uri> resolve(Song song, {bool refreshRemoteUrl = false}) async {
    if (song.source == MusicSource.local) {
      if (song.filePath.trim().isEmpty) {
        throw const PlaybackSourceException('歌曲缺少本地文件路径');
      }
      if (!await _localFileExists(song.filePath)) {
        throw PlaybackSourceException('本地歌曲文件不存在: ${song.filePath}');
      }
      return Uri.file(song.filePath);
    }

    final requestSong = refreshRemoteUrl ? song.copyWith(playUrl: '') : song;
    final url = (await _resolveKugouUrl(requestSong)).trim();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const PlaybackSourceException('未获取到有效的歌曲播放地址');
    }
    return uri;
  }

  static Future<bool> _defaultLocalFileExists(String path) {
    return File(path).exists();
  }
}
