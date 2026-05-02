class Song {
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String filePath;
  final String coverPath;
  final String coverUrl;
  final MusicSource source;
  final String hash;
  final String albumId;
  final String albumAudioId;
  final String playUrl;
  final String audioId;

  const Song({
    required this.title,
    required this.artist,
    this.album = '',
    required this.duration,
    this.filePath = '',
    this.coverPath = '',
    this.coverUrl = '',
    this.source = MusicSource.local,
    this.hash = '',
    this.albumId = '',
    this.albumAudioId = '',
    this.playUrl = '',
    this.audioId = '',
  });

  Song copyWith({
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    String? filePath,
    String? coverPath,
    String? coverUrl,
    MusicSource? source,
    String? hash,
    String? albumId,
    String? albumAudioId,
    String? playUrl,
    String? audioId,
  }) {
    return Song(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      filePath: filePath ?? this.filePath,
      coverPath: coverPath ?? this.coverPath,
      coverUrl: coverUrl ?? this.coverUrl,
      source: source ?? this.source,
      hash: hash ?? this.hash,
      albumId: albumId ?? this.albumId,
      albumAudioId: albumAudioId ?? this.albumAudioId,
      playUrl: playUrl ?? this.playUrl,
      audioId: audioId ?? this.audioId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'artist': artist,
      'album': album,
      'durationMs': duration.inMilliseconds,
      'filePath': filePath,
      'coverPath': coverPath,
      'coverUrl': coverUrl,
      'source': source.name,
      'hash': hash,
      'albumId': albumId,
      'albumAudioId': albumAudioId,
      'playUrl': playUrl,
      'audioId': audioId,
    };
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    final sourceName = json['source'] as String? ?? MusicSource.local.name;
    return Song(
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '未知歌手',
      album: json['album'] as String? ?? '',
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      filePath: json['filePath'] as String? ?? '',
      coverPath: json['coverPath'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
      source: MusicSource.values.firstWhere(
        (value) => value.name == sourceName,
        orElse: () => MusicSource.local,
      ),
      hash: json['hash'] as String? ?? '',
      albumId: json['albumId']?.toString() ?? '',
      albumAudioId: json['albumAudioId']?.toString() ?? '',
      playUrl: json['playUrl'] as String? ?? '',
      audioId: json['audioId']?.toString() ?? '',
    );
  }
}

enum MusicSource { local, kugou }

enum PlayMode { sequential, singleRepeat, shuffle }

enum BoundaryAction { restartCurrent, keepPlaying }

enum PlaybackActionResult { played, restartedCurrent, reachedBoundary }

enum AutoScanInterval { off, daily, weekly, monthly }

final List<Song> demoSongs = [
  const Song(
    title: '晴天',
    artist: '周杰伦',
    album: '叶惠美',
    duration: Duration(minutes: 4, seconds: 29),
  ),
  const Song(
    title: '夜曲',
    artist: '周杰伦',
    album: '十一月的萧邦',
    duration: Duration(minutes: 3, seconds: 46),
  ),
  const Song(
    title: '稻香',
    artist: '周杰伦',
    album: '魔杰座',
    duration: Duration(minutes: 3, seconds: 59),
  ),
  const Song(
    title: '七里香',
    artist: '周杰伦',
    album: '七里香',
    duration: Duration(minutes: 4, seconds: 59),
  ),
  const Song(
    title: '简单爱',
    artist: '周杰伦',
    album: '范特西',
    duration: Duration(minutes: 4, seconds: 30),
  ),
  const Song(
    title: '告白气球',
    artist: '周杰伦',
    album: '周杰伦的床边故事',
    duration: Duration(minutes: 3, seconds: 35),
  ),
  const Song(
    title: '青花瓷',
    artist: '周杰伦',
    album: '我很忙',
    duration: Duration(minutes: 3, seconds: 59),
  ),
  const Song(
    title: '以父之名',
    artist: '周杰伦',
    album: '叶惠美',
    duration: Duration(minutes: 5, seconds: 42),
  ),
  const Song(
    title: '安静',
    artist: '周杰伦',
    album: '范特西',
    duration: Duration(minutes: 5, seconds: 33),
  ),
  const Song(
    title: '搁浅',
    artist: '周杰伦',
    album: '七里香',
    duration: Duration(minutes: 4, seconds: 18),
  ),
  const Song(
    title: '反方向的钟',
    artist: '周杰伦',
    album: 'Jay',
    duration: Duration(minutes: 4, seconds: 17),
  ),
  const Song(
    title: '等你下课',
    artist: '周杰伦',
    album: '等你下课',
    duration: Duration(minutes: 4, seconds: 27),
  ),
];
