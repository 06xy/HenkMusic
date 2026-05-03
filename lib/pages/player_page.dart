import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/song.dart';
import '../services/music_service.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _discController;
  final ScrollController _lyricsScrollController = ScrollController();
  final Map<int, GlobalKey> _lyricKeys = {};

  bool _isDragging = false;
  double _dragValue = 0;
  bool _showLyrics = false;
  int _lastLyricIndex = -1;
  double _lyricsViewportHeight = 0;

  List<Song> get _songs => musicService.activeSongs;
  Song get _currentSong => musicService.currentSong;
  Duration get _currentPosition => musicService.currentPosition;
  PlayMode get _playMode => musicService.playMode;
  bool get _isPlaying => musicService.isPlaying;

  @override
  void initState() {
    super.initState();
    musicService.addListener(_onServiceChanged);
    _discController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    if (_isPlaying) _discController.repeat();
  }

  @override
  void dispose() {
    musicService.removeListener(_onServiceChanged);
    _discController.dispose();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (_isPlaying) {
      if (!_discController.isAnimating) _discController.repeat();
    } else {
      _discController.stop();
    }
    if (mounted) setState(() {});
  }

  Future<void> _togglePlayPause() => musicService.togglePlayPause();

  Future<void> _nextSong() async {
    _lastLyricIndex = -1;
    try {
      _showPlaybackResult(await musicService.next());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _previousSong() async {
    _lastLyricIndex = -1;
    try {
      _showPlaybackResult(await musicService.previous());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _playSongLocal(Song song) async {
    _lastLyricIndex = -1;
    try {
      await musicService.playSong(song);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _showPlaybackResult(PlaybackActionResult result) {
    if (!mounted) return;
    switch (result) {
      case PlaybackActionResult.played:
        return;
      case PlaybackActionResult.restartedCurrent:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已重新播放当前歌曲')));
        return;
      case PlaybackActionResult.reachedBoundary:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已经没有更多歌曲了')));
        return;
    }
  }

  Future<void> _seekTo(Duration position) => musicService.seek(position);

  Future<void> _cyclePlayMode() => musicService.cyclePlayMode();

  Future<void> _downloadCurrentSong() async {
    try {
      final dir = await musicService.downloadCurrentKugouSong();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已下载到 ${dir.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return '--:--';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  IconData _playModeIcon() {
    switch (_playMode) {
      case PlayMode.sequential:
        return Icons.repeat_rounded;
      case PlayMode.singleRepeat:
        return Icons.repeat_one_rounded;
      case PlayMode.shuffle:
        return Icons.shuffle_rounded;
    }
  }

  String _playModeLabel() {
    switch (_playMode) {
      case PlayMode.sequential:
        return '顺序播放';
      case PlayMode.singleRepeat:
        return '单曲循环';
      case PlayMode.shuffle:
        return '随机播放';
    }
  }

  int _currentLyricIndex() {
    final lyrics = musicService.getLyricLines(
      _currentSong.title,
      _currentSong.artist,
    );
    if (lyrics.isEmpty) return 0;
    int idx = 0;
    for (int i = 0; i < lyrics.length; i++) {
      if (_currentPosition >= lyrics[i].time) idx = i;
    }
    return idx;
  }

  GlobalKey _lyricKey(int index) {
    return _lyricKeys.putIfAbsent(index, () => GlobalKey());
  }

  void _syncLyricKeys(int length) {
    _lyricKeys.removeWhere((index, _) => index >= length);
  }

  void _autoScrollLyrics() {
    final currentIndex = _currentLyricIndex();
    if (currentIndex == _lastLyricIndex) return;
    _lastLyricIndex = currentIndex;
    if (!_lyricsScrollController.hasClients) return;

    final lyrics = musicService.getLyricLines(
      _currentSong.title,
      _currentSong.artist,
    );
    if (lyrics.length <= 1) return;

    final listContext = _lyricsScrollController.position.context.storageContext;
    final itemContext = _lyricKeys[currentIndex]?.currentContext;
    final listBox = listContext.findRenderObject() as RenderBox?;
    final itemBox = itemContext?.findRenderObject() as RenderBox?;
    if (listBox == null || itemBox == null) return;
    if (_lyricsViewportHeight != listBox.size.height && mounted) {
      setState(() => _lyricsViewportHeight = listBox.size.height);
    }

    final listCenter = listBox.size.height / 2;
    final itemTop = itemBox.localToGlobal(Offset.zero, ancestor: listBox).dy;
    final itemCenter = itemTop + itemBox.size.height / 2;
    final targetOffset =
        _lyricsScrollController.offset + itemCenter - listCenter;
    final maxScroll = _lyricsScrollController.position.maxScrollExtent;
    _lyricsScrollController.animateTo(
      targetOffset.clamp(0.0, maxScroll),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _onLyricTap(int index) {
    final lyrics = musicService.getLyricLines(
      _currentSong.title,
      _currentSong.artist,
    );
    if (index < lyrics.length) _seekTo(lyrics[index].time);
  }

  void _showPlaylistSheet() {
    final colorScheme = Theme.of(context).colorScheme;
    final songs = _songs;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          builder: (ctx, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        Text(
                          '播放列表',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${songs.length}首',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: songs.length,
                      itemBuilder: (ctx, index) {
                        final song = songs[index];
                        final isCurrent =
                            index == musicService.currentSongIndex;
                        return ListTile(
                          leading: isCurrent
                              ? Icon(
                                  Icons.volume_up_rounded,
                                  color: colorScheme.primary,
                                  size: 20,
                                )
                              : Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: colorScheme.onSurface.withOpacity(
                                      0.4,
                                    ),
                                    fontSize: 14,
                                  ),
                                ),
                          title: Text(
                            song.title,
                            style: TextStyle(
                              color: isCurrent
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                              fontWeight: isCurrent
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Text(
                            song.artist,
                            style: TextStyle(
                              color: colorScheme.onSurface.withOpacity(0.5),
                              fontSize: 12,
                            ),
                          ),
                          trailing: Text(
                            _formatDuration(song.duration),
                            style: TextStyle(
                              color: colorScheme.onSurface.withOpacity(0.4),
                              fontSize: 12,
                            ),
                          ),
                          onTap: () {
                            _playSongLocal(song);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    if (_songs.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
          ),
          title: const Text('播放'),
        ),
        body: const Center(child: Text('未找到歌曲')),
      );
    }

    final discSize = min(size.width * 0.65, 280.0);
    final duration = _currentSong.duration;
    final progress = duration.inMilliseconds > 0
        ? _currentPosition.inMilliseconds / duration.inMilliseconds
        : 0.0;

    if (_showLyrics) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoScrollLyrics());
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [colorScheme.primaryContainer, colorScheme.surface],
            stops: const [0.0, 0.6],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context, colorScheme),
              if (_showLyrics)
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _showLyrics = false),
                    child: _buildLyricsView(colorScheme),
                  ),
                )
              else ...[
                const Spacer(flex: 1),
                GestureDetector(
                  onTap: () {
                    setState(() => _showLyrics = true);
                    _lastLyricIndex = -1;
                  },
                  child: _buildDisc(discSize, colorScheme),
                ),
                const Spacer(flex: 1),
              ],
              _buildProgressBar(progress, colorScheme),
              const SizedBox(height: 20),
              _buildControls(colorScheme),
              const SizedBox(height: 12),
              _buildBottomActions(colorScheme),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, ColorScheme colorScheme) {
    final albumText = _currentSong.album.isEmpty
        ? _currentSong.artist
        : '${_currentSong.artist}  ·  ${_currentSong.album}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
            color: colorScheme.onSurface,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  _currentSong.title,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  albumText,
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.6),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.share_rounded, size: 22),
            color: colorScheme.onSurface,
          ),
        ],
      ),
    );
  }

  Widget _buildDisc(double discSize, ColorScheme colorScheme) {
    Widget discContent;
    if (_currentSong.coverPath.isNotEmpty) {
      discContent = ClipOval(
        child: Image.file(
          File(_currentSong.coverPath),
          width: discSize,
          height: discSize,
          cacheWidth: 700,
          cacheHeight: 700,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              _buildDefaultDisc(discSize, colorScheme),
        ),
      );
    } else if (_currentSong.coverUrl.isNotEmpty) {
      discContent = ClipOval(
        child: Image.network(
          _currentSong.coverUrl,
          width: discSize,
          height: discSize,
          cacheWidth: 700,
          cacheHeight: 700,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              _buildDefaultDisc(discSize, colorScheme),
        ),
      );
    } else {
      discContent = _buildDefaultDisc(discSize, colorScheme);
    }

    return AnimatedBuilder(
      animation: _discController,
      builder: (context, child) =>
          Transform.rotate(angle: _discController.value * 2 * pi, child: child),
      child: discContent,
    );
  }

  Widget _buildDefaultDisc(double discSize, ColorScheme colorScheme) {
    return Container(
      width: discSize,
      height: discSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.primary.withOpacity(0.1),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
          width: 8,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.2),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: discSize * 0.45,
            height: discSize * 0.45,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.surface,
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.15),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.music_note_rounded,
              size: discSize * 0.18,
              color: colorScheme.primary.withOpacity(0.6),
            ),
          ),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.onSurface.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsView(ColorScheme colorScheme) {
    final lyrics = musicService.getLyricLines(
      _currentSong.title,
      _currentSong.artist,
    );
    final currentIndex = _currentLyricIndex();
    _syncLyricKeys(lyrics.length);

    if (lyrics.length <= 1) {
      return Center(
        child: Text(
          lyrics.isEmpty ? '暂无歌词' : lyrics.first.text,
          style: TextStyle(
            fontSize: 18,
            color: colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      );
    }

    return ShaderMask(
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: const [0.0, 0.08, 0.92, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _lyricsScrollController,
        padding: EdgeInsets.symmetric(
          vertical: max(_lyricsViewportHeight / 2 - 40, 40),
          horizontal: 32,
        ),
        itemCount: lyrics.length,
        itemBuilder: (context, index) {
          final isCurrent = index == currentIndex;
          return GestureDetector(
            key: _lyricKey(index),
            onTap: () => _onLyricTap(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontSize: isCurrent ? 18 : 15,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  color: isCurrent
                      ? colorScheme.onSurface
                      : colorScheme.onSurface.withOpacity(0.35),
                  height: 1.7,
                ),
                child: _buildLyricLine(lyrics[index], isCurrent, colorScheme),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLyricLine(
    LyricLine line,
    bool isCurrent,
    ColorScheme colorScheme,
  ) {
    final text = line.text.isEmpty ? '...' : line.text;
    if (!line.hasWordTiming || !isCurrent) {
      return Text(text, textAlign: TextAlign.center, softWrap: true);
    }

    final baseStyle = DefaultTextStyle.of(context).style;
    return RichText(
      textAlign: TextAlign.center,
      softWrap: true,
      text: TextSpan(
        style: baseStyle.copyWith(
          color: colorScheme.onSurface.withValues(alpha: 0.38),
        ),
        children: line.words.map((word) {
          final reveal = _lyricWordReveal(word);
          return TextSpan(
            text: word.text,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(
                alpha: 0.34 + 0.66 * reveal,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  double _lyricWordReveal(LyricWord word) {
    if (word.text.trim().isEmpty) return 1;
    final currentMs = _currentPosition.inMilliseconds;
    final beginMs = word.begin.inMilliseconds;
    final endMs = max(word.end.inMilliseconds, beginMs + 1);
    if (currentMs >= endMs) return 1;

    const preheatMs = 180;
    if (currentMs < beginMs) {
      final warmup = ((currentMs - (beginMs - preheatMs)) / preheatMs).clamp(
        0.0,
        1.0,
      );
      return 0.18 * Curves.easeOutCubic.transform(warmup);
    }

    final progress = ((currentMs - beginMs) / (endMs - beginMs)).clamp(
      0.0,
      1.0,
    );
    return 0.18 + 0.82 * Curves.easeInOutCubic.transform(progress);
  }

  Widget _buildProgressBar(double progress, ColorScheme colorScheme) {
    final duration = _currentSong.duration;
    final currentMs = _isDragging
        ? _dragValue * duration.inMilliseconds
        : _currentPosition.inMilliseconds.toDouble();
    final currentDur = Duration(milliseconds: currentMs.toInt());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.primary.withOpacity(0.15),
              thumbColor: colorScheme.primary,
              overlayColor: colorScheme.primary.withOpacity(0.2),
            ),
            child: Slider(
              value: (_isDragging ? _dragValue : progress).clamp(0.0, 1.0),
              onChangeStart: duration == Duration.zero
                  ? null
                  : (v) => setState(() {
                      _isDragging = true;
                      _dragValue = v;
                    }),
              onChanged: duration == Duration.zero
                  ? null
                  : (v) => setState(() => _dragValue = v),
              onChangeEnd: duration == Duration.zero
                  ? null
                  : (v) {
                      _seekTo(
                        Duration(
                          milliseconds: (v * duration.inMilliseconds).toInt(),
                        ),
                      );
                      setState(() => _isDragging = false);
                    },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(currentDur),
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            onPressed: _previousSong,
            icon: const Icon(Icons.skip_previous_rounded),
            iconSize: 36,
            color: colorScheme.onSurface,
          ),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primary,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: IconButton(
              onPressed: _togglePlayPause,
              icon: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
              color: colorScheme.onPrimary,
              iconSize: 36,
              padding: EdgeInsets.zero,
            ),
          ),
          IconButton(
            onPressed: _nextSong,
            icon: const Icon(Icons.skip_next_rounded),
            iconSize: 36,
            color: colorScheme.onSurface,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Tooltip(
            message: _playModeLabel(),
            child: IconButton(
              onPressed: _cyclePlayMode,
              icon: Icon(_playModeIcon()),
              color: _playMode == PlayMode.sequential
                  ? colorScheme.onSurface.withOpacity(0.5)
                  : colorScheme.primary,
              iconSize: 22,
            ),
          ),
          if (musicService.musicSource == MusicSource.kugou)
            IconButton(
              onPressed: _downloadCurrentSong,
              icon: const Icon(Icons.download_rounded),
              color: colorScheme.onSurface.withOpacity(0.5),
              iconSize: 22,
              tooltip: '下载到本地',
            ),
          IconButton(
            onPressed: _showPlaylistSheet,
            icon: const Icon(Icons.playlist_play_rounded),
            color: colorScheme.onSurface.withOpacity(0.5),
            iconSize: 24,
          ),
        ],
      ),
    );
  }
}
