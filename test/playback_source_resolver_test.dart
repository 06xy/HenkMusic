import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/song.dart';
import 'package:music_player/services/playback_source_resolver.dart';

void main() {
  group('PlaybackSourceResolver', () {
    test('rejects a local song without a file path', () async {
      final resolver = PlaybackSourceResolver(
        resolveKugouUrl: (_) async => 'https://example.com/song.mp3',
      );

      await expectLater(
        resolver.resolve(
          const Song(
            title: 'Missing',
            artist: 'Artist',
            duration: Duration.zero,
          ),
        ),
        throwsA(
          isA<PlaybackSourceException>().having(
            (error) => error.message,
            'message',
            contains('缺少本地文件路径'),
          ),
        ),
      );
    });

    test('rejects a missing local file', () async {
      final resolver = PlaybackSourceResolver(
        resolveKugouUrl: (_) async => 'https://example.com/song.mp3',
        localFileExists: (_) async => false,
      );

      await expectLater(
        resolver.resolve(
          const Song(
            title: 'Missing',
            artist: 'Artist',
            duration: Duration.zero,
            filePath: 'C:/missing/song.mp3',
          ),
        ),
        throwsA(isA<PlaybackSourceException>()),
      );
    });

    test('returns a local file URI only after existence validation', () async {
      var checkedPath = '';
      final resolver = PlaybackSourceResolver(
        resolveKugouUrl: (_) async => 'https://example.com/song.mp3',
        localFileExists: (path) async {
          checkedPath = path;
          return true;
        },
      );

      final uri = await resolver.resolve(
        const Song(
          title: 'Local',
          artist: 'Artist',
          duration: Duration.zero,
          filePath: 'C:/music/song.mp3',
        ),
      );

      expect(checkedPath, 'C:/music/song.mp3');
      expect(uri.scheme, 'file');
    });

    test('rejects an invalid remote playback URL', () async {
      final resolver = PlaybackSourceResolver(resolveKugouUrl: (_) async => '');

      await expectLater(
        resolver.resolve(
          const Song(
            title: 'Remote',
            artist: 'Artist',
            duration: Duration.zero,
            source: MusicSource.kugou,
            hash: 'hash',
          ),
        ),
        throwsA(
          isA<PlaybackSourceException>().having(
            (error) => error.message,
            'message',
            contains('有效的歌曲播放地址'),
          ),
        ),
      );
    });

    test('refresh ignores a stale cached remote URL', () async {
      Song? requestedSong;
      final resolver = PlaybackSourceResolver(
        resolveKugouUrl: (song) async {
          requestedSong = song;
          return 'https://example.com/refreshed.mp3';
        },
      );
      const song = Song(
        title: 'Remote',
        artist: 'Artist',
        duration: Duration.zero,
        source: MusicSource.kugou,
        hash: 'hash',
        playUrl: 'https://example.com/stale.mp3',
      );

      final uri = await resolver.resolve(song, refreshRemoteUrl: true);

      expect(requestedSong?.playUrl, isEmpty);
      expect(uri.toString(), 'https://example.com/refreshed.mp3');
    });
  });
}
