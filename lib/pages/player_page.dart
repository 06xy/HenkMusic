import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/song.dart';
import '../services/music_service.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
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
  bool get _isSwitchingTrack => musicService.isSwitchingTrack;

  @override
  void initState() {
    super.initState();
    musicService.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    musicService.removeListener(_onServiceChanged);
    _lyricsScrollController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
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
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
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
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.4,
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
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                              fontSize: 12,
                            ),
                          ),
                          trailing: Text(
                            _formatDuration(song.duration),
                            style: TextStyle(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.4,
                              ),
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
    final isLandscape = size.width > size.height;
    final isTablet = size.shortestSide >= 600;
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

    final duration = _currentSong.duration;
    final progress = duration.inMilliseconds > 0
        ? _currentPosition.inMilliseconds / duration.inMilliseconds
        : 0.0;

    if (_showLyrics || isLandscape) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoScrollLyrics());
    }

    if (isLandscape && isTablet) {
      return _buildTabletLandscapePlayer(colorScheme, size, progress);
    }
    if (isLandscape) {
      return _buildPhoneLandscapePlayer(colorScheme, size, progress);
    }
    return _buildPortraitApplePlayer(
      colorScheme,
      size,
      progress,
      isTablet: isTablet,
    );
  }

  Widget _buildPortraitApplePlayer(
    ColorScheme colorScheme,
    Size size,
    double progress, {
    required bool isTablet,
  }) {
    final darkScheme = _darkPlayerScheme(colorScheme);
    final artworkSize = min(
      size.width - (isTablet ? 144 : 56),
      size.height * (isTablet ? 0.44 : 0.4),
    );
    return Scaffold(
      key: Key(isTablet ? 'player-tablet-portrait' : 'player-phone-portrait'),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBlurredCoverBackground(colorScheme),
          _buildAlbumBackdropScrim(),
          SafeArea(
            child: Column(
              children: [
                _buildAppleTopBar(darkScheme),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _showLyrics
                        ? Padding(
                            key: const ValueKey('portrait-lyrics'),
                            padding: EdgeInsets.symmetric(
                              horizontal: isTablet ? 72 : 24,
                            ),
                            child: _buildLyricsView(
                              darkScheme,
                              horizontalPadding: 0,
                              textAlign: TextAlign.left,
                              activeFontSize: isTablet ? 38 : 30,
                              inactiveFontSize: isTablet ? 28 : 22,
                              lyricLineHeight: 1.32,
                            ),
                          )
                        : Center(
                            key: const ValueKey('portrait-artwork'),
                            child: GestureDetector(
                              onTap: _toggleLyrics,
                              child: _buildAlbumArtwork(
                                artworkSize,
                                darkScheme,
                                borderRadius: isTablet ? 24 : 18,
                              ),
                            ),
                          ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isTablet ? 72 : 28),
                  child: _buildSongInfoOnDark(titleSize: isTablet ? 27 : 22),
                ),
                SizedBox(height: isTablet ? 18 : 12),
                _buildProgressBar(
                  progress,
                  darkScheme,
                  horizontalPadding: isTablet ? 56 : 18,
                ),
                SizedBox(height: isTablet ? 18 : 12),
                _buildControls(
                  darkScheme,
                  playButtonSize: isTablet ? 72 : 64,
                  controlIconSize: isTablet ? 40 : 36,
                ),
                SizedBox(height: isTablet ? 10 : 4),
                _buildAppleActionBar(darkScheme, showLyricsButton: true),
                SizedBox(height: isTablet ? 18 : 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneLandscapePlayer(
    ColorScheme colorScheme,
    Size size,
    double progress,
  ) {
    final darkScheme = _darkPlayerScheme(colorScheme);
    final artworkSize = min(size.height * 0.52, size.width * 0.28);
    return Scaffold(
      key: const Key('player-phone-landscape'),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBlurredCoverBackground(colorScheme),
          _buildAlbumBackdropScrim(),
          SafeArea(
            child: Column(
              children: [
                _buildAppleTopBar(darkScheme, compact: true),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 32, 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: max(artworkSize, 160),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: _buildAlbumArtwork(
                                  artworkSize,
                                  darkScheme,
                                  borderRadius: 16,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildSongInfoOnDark(titleSize: 18),
                            ],
                          ),
                        ),
                        const SizedBox(width: 36),
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(
                                child: _buildLyricsView(
                                  darkScheme,
                                  horizontalPadding: 0,
                                  textAlign: TextAlign.left,
                                  activeFontSize: 25,
                                  inactiveFontSize: 19,
                                  lyricLineHeight: 1.25,
                                ),
                              ),
                              _buildProgressBar(
                                progress,
                                darkScheme,
                                horizontalPadding: 0,
                                compact: true,
                              ),
                              _buildControls(
                                darkScheme,
                                playButtonSize: 50,
                                controlIconSize: 30,
                                horizontalPadding: 8,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleLyrics() {
    setState(() {
      _showLyrics = !_showLyrics;
      _lastLyricIndex = -1;
    });
  }

  Widget _buildTabletLandscapePlayer(
    ColorScheme colorScheme,
    Size size,
    double progress,
  ) {
    final albumSize = min(size.height * 0.5, size.width * 0.34);
    final darkScheme = _darkPlayerScheme(colorScheme);
    return Scaffold(
      key: const Key('player-tablet-landscape'),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBlurredCoverBackground(colorScheme),
          _buildAlbumBackdropScrim(),
          SafeArea(
            child: Column(
              children: [
                _buildAppleTopBar(darkScheme),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(64, 0, 72, 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: max(albumSize, 280),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: _buildAlbumArtwork(
                                  albumSize,
                                  darkScheme,
                                  borderRadius: 22,
                                ),
                              ),
                              const SizedBox(height: 28),
                              _buildSongInfoOnDark(),
                              const SizedBox(height: 20),
                              _buildProgressBar(progress, darkScheme),
                              const SizedBox(height: 16),
                              _buildControls(darkScheme),
                              const SizedBox(height: 4),
                              _buildAppleActionBar(
                                darkScheme,
                                showLyricsButton: false,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 72),
                        Expanded(
                          child: _buildLyricsView(
                            darkScheme,
                            largeText: true,
                            horizontalPadding: 0,
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ColorScheme _darkPlayerScheme(ColorScheme base) {
    return base.copyWith(
      primary: Colors.white,
      onPrimary: Colors.black,
      surface: Colors.black,
      onSurface: Colors.white,
      outline: Colors.white70,
      outlineVariant: Colors.white24,
      shadow: Colors.black,
    );
  }

  Widget _buildBlurredCoverBackground(ColorScheme colorScheme) {
    final image = _coverImageProvider();
    if (image == null) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primary.withValues(alpha: 0.45),
              colorScheme.secondaryContainer.withValues(alpha: 0.55),
              colorScheme.surface,
            ],
          ),
        ),
      );
    }

    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
      child: Transform.scale(
        scale: 1.16,
        child: Image(
          image: image,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: colorScheme.surface),
        ),
      ),
    );
  }

  Widget _buildAlbumBackdropScrim() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.55, -0.25),
          radius: 1.2,
          colors: [
            Colors.white.withValues(alpha: 0.05),
            Colors.black.withValues(alpha: 0.28),
            Colors.black.withValues(alpha: 0.72),
          ],
          stops: const [0.0, 0.52, 1.0],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.06),
              Colors.black.withValues(alpha: 0.18),
              Colors.black.withValues(alpha: 0.56),
            ],
            stops: const [0.0, 0.42, 1.0],
          ),
        ),
      ),
    );
  }

  ImageProvider? _coverImageProvider() {
    if (_currentSong.coverPath.isNotEmpty) {
      return FileImage(File(_currentSong.coverPath));
    }
    if (_currentSong.coverUrl.isNotEmpty) {
      return NetworkImage(_currentSong.coverUrl);
    }
    return null;
  }

  Widget _buildSongInfoOnDark({double titleSize = 24}) {
    final albumText = _currentSong.album.isEmpty
        ? _currentSong.artist
        : '${_currentSong.artist}  ·  ${_currentSong.album}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _currentSong.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ).copyWith(fontSize: titleSize),
        ),
        const SizedBox(height: 6),
        Text(
          albumText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.68),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildAppleTopBar(ColorScheme colorScheme, {bool compact = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, compact ? 2 : 8, 18, 0),
      child: Row(
        children: [
          _buildGlassIconButton(
            icon: Icons.keyboard_arrow_down_rounded,
            colorScheme: colorScheme,
            iconSize: compact ? 28 : 32,
            size: compact ? 38 : 44,
            tooltip: '收起播放页',
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          Text(
            '正在播放',
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.68),
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _buildGlassIconButton(
            icon: Icons.more_horiz_rounded,
            colorScheme: colorScheme,
            iconSize: compact ? 22 : 24,
            size: compact ? 38 : 44,
            tooltip: '播放列表',
            onPressed: _showPlaylistSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildGlassIconButton({
    required IconData icon,
    required ColorScheme colorScheme,
    required VoidCallback onPressed,
    double iconSize = 24,
    double size = 44,
    String? tooltip,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.12),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: iconSize,
        color: colorScheme.onSurface.withValues(alpha: 0.86),
        padding: EdgeInsets.zero,
        tooltip: tooltip,
      ),
    );
  }

  Widget _buildAlbumArtwork(
    double discSize,
    ColorScheme colorScheme, {
    double? borderRadius,
  }) {
    final fallback = borderRadius == null
        ? _buildDefaultDisc(discSize, colorScheme)
        : _buildDefaultAlbumArtwork(
            discSize,
            colorScheme,
            borderRadius: borderRadius,
          );
    Widget discContent;
    if (_currentSong.coverPath.isNotEmpty) {
      discContent = _clipArtwork(
        child: Image.file(
          File(_currentSong.coverPath),
          width: discSize,
          height: discSize,
          cacheWidth: 700,
          cacheHeight: 700,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
        borderRadius: borderRadius,
      );
    } else if (_currentSong.coverUrl.isNotEmpty) {
      discContent = _clipArtwork(
        child: Image.network(
          _currentSong.coverUrl,
          width: discSize,
          height: discSize,
          cacheWidth: 700,
          cacheHeight: 700,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
        borderRadius: borderRadius,
      );
    } else {
      discContent = fallback;
    }

    if (borderRadius == null) return discContent;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: discContent,
    );
  }

  Widget _buildDefaultAlbumArtwork(
    double size,
    ColorScheme colorScheme, {
    required double borderRadius,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.onSurface.withValues(alpha: 0.2),
            colorScheme.surface.withValues(alpha: 0.72),
          ],
        ),
        border: Border.all(
          color: colorScheme.onSurface.withValues(alpha: 0.12),
        ),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.26,
        color: colorScheme.onSurface.withValues(alpha: 0.72),
      ),
    );
  }

  Widget _clipArtwork({required Widget child, double? borderRadius}) {
    if (borderRadius == null) return ClipOval(child: child);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: child,
    );
  }

  Widget _buildDefaultDisc(double discSize, ColorScheme colorScheme) {
    return Container(
      width: discSize,
      height: discSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.primary.withValues(alpha: 0.1),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.2),
          width: 8,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.2),
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
                color: colorScheme.outline.withValues(alpha: 0.15),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.music_note_rounded,
              size: discSize * 0.18,
              color: colorScheme.primary.withValues(alpha: 0.6),
            ),
          ),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsView(
    ColorScheme colorScheme, {
    bool largeText = false,
    double horizontalPadding = 32,
    TextAlign textAlign = TextAlign.center,
    double? activeFontSize,
    double? inactiveFontSize,
    double? lyricLineHeight,
  }) {
    final resolvedActiveFontSize = activeFontSize ?? (largeText ? 40 : 18);
    final resolvedInactiveFontSize = inactiveFontSize ?? (largeText ? 30 : 15);
    final resolvedLineHeight = lyricLineHeight ?? (largeText ? 1.28 : 1.7);
    final usesLargeTypography = resolvedActiveFontSize >= 28;
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
          textAlign: textAlign,
          style: TextStyle(
            fontSize: resolvedInactiveFontSize,
            color: colorScheme.onSurface.withValues(alpha: 0.5),
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
          vertical: max(
            _lyricsViewportHeight / 2 -
                (usesLargeTypography ? resolvedActiveFontSize * 1.6 : 40),
            32,
          ),
          horizontal: horizontalPadding,
        ),
        itemCount: lyrics.length,
        itemBuilder: (context, index) {
          final isCurrent = index == currentIndex;
          return GestureDetector(
            key: _lyricKey(index),
            onTap: () => _onLyricTap(index),
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: usesLargeTypography ? 10 : 8,
              ),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontSize: isCurrent
                      ? resolvedActiveFontSize
                      : resolvedInactiveFontSize,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                  color: isCurrent
                      ? colorScheme.onSurface
                      : colorScheme.onSurface.withValues(
                          alpha: usesLargeTypography ? 0.38 : 0.35,
                        ),
                  height: resolvedLineHeight,
                ),
                child: _buildLyricLine(
                  lyrics[index],
                  isCurrent,
                  colorScheme,
                  textAlign: textAlign,
                ),
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
    ColorScheme colorScheme, {
    TextAlign textAlign = TextAlign.center,
  }) {
    final text = line.text.isEmpty ? '...' : line.text;
    if (!line.hasWordTiming || !isCurrent) {
      return Text(text, textAlign: textAlign, softWrap: true);
    }

    final baseStyle = DefaultTextStyle.of(context).style;
    return RichText(
      textAlign: textAlign,
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

  Widget _buildProgressBar(
    double progress,
    ColorScheme colorScheme, {
    double horizontalPadding = 28,
    bool compact = false,
  }) {
    final duration = _currentSong.duration;
    final currentMs = _isDragging
        ? _dragValue * duration.inMilliseconds
        : _currentPosition.inMilliseconds.toDouble();
    final currentDur = Duration(milliseconds: currentMs.toInt());

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: compact ? 2.5 : 3,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: compact ? 5 : 6,
              ),
              overlayShape: RoundSliderOverlayShape(
                overlayRadius: compact ? 10 : 14,
              ),
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.primary.withValues(alpha: 0.18),
              thumbColor: colorScheme.primary,
              overlayColor: colorScheme.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: (_isDragging ? _dragValue : progress).clamp(0.0, 1.0),
              onChangeStart: duration == Duration.zero || _isSwitchingTrack
                  ? null
                  : (v) => setState(() {
                      _isDragging = true;
                      _dragValue = v;
                    }),
              onChanged: duration == Duration.zero || _isSwitchingTrack
                  ? null
                  : (v) => setState(() => _dragValue = v),
              onChangeEnd: duration == Duration.zero || _isSwitchingTrack
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
                    color: colorScheme.onSurface.withValues(alpha: 0.52),
                    fontSize: compact ? 10 : 12,
                  ),
                ),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.52),
                    fontSize: compact ? 10 : 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(
    ColorScheme colorScheme, {
    double playButtonSize = 64,
    double controlIconSize = 36,
    double horizontalPadding = 24,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            onPressed: _isSwitchingTrack ? null : _previousSong,
            icon: const Icon(Icons.skip_previous_rounded),
            iconSize: controlIconSize,
            color: colorScheme.onSurface,
          ),
          Container(
            width: playButtonSize,
            height: playButtonSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primary,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.28),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: IconButton(
              onPressed: _isSwitchingTrack ? null : _togglePlayPause,
              icon: _isSwitchingTrack
                  ? SizedBox(
                      width: controlIconSize * 0.62,
                      height: controlIconSize * 0.62,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
              color: colorScheme.onPrimary,
              iconSize: controlIconSize,
              padding: EdgeInsets.zero,
            ),
          ),
          IconButton(
            onPressed: _isSwitchingTrack ? null : _nextSong,
            icon: const Icon(Icons.skip_next_rounded),
            iconSize: controlIconSize,
            color: colorScheme.onSurface,
          ),
        ],
      ),
    );
  }

  Widget _buildAppleActionBar(
    ColorScheme colorScheme, {
    required bool showLyricsButton,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (showLyricsButton)
            IconButton(
              onPressed: _toggleLyrics,
              icon: const Icon(Icons.lyrics_rounded),
              color: _showLyrics
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.55),
              iconSize: 23,
              tooltip: _showLyrics ? '显示专辑封面' : '显示歌词',
            ),
          Tooltip(
            message: _playModeLabel(),
            child: IconButton(
              onPressed: _cyclePlayMode,
              icon: Icon(_playModeIcon()),
              color: _playMode == PlayMode.sequential
                  ? colorScheme.onSurface.withValues(alpha: 0.55)
                  : colorScheme.primary,
              iconSize: 22,
            ),
          ),
          if (musicService.musicSource == MusicSource.kugou)
            IconButton(
              onPressed: _downloadCurrentSong,
              icon: const Icon(Icons.download_rounded),
              color: colorScheme.onSurface.withValues(alpha: 0.55),
              iconSize: 22,
              tooltip: '下载到本地',
            ),
          IconButton(
            onPressed: _showPlaylistSheet,
            icon: const Icon(Icons.playlist_play_rounded),
            color: colorScheme.onSurface.withValues(alpha: 0.55),
            iconSize: 24,
            tooltip: '播放列表',
          ),
        ],
      ),
    );
  }
}
