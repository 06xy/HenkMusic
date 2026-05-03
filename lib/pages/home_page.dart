import 'dart:io';
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/song.dart';
import '../widgets/bottom_player_bar.dart';
import 'player_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    musicService.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    musicService.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  List<Song> get _songs => musicService.activeSongs;

  Song get _currentSong => musicService.currentSong;

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

  Future<void> _nextSong() async {
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
    try {
      _showPlaybackResult(await musicService.previous());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _openPlayerPage() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const PlayerPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final tween = Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  Future<void> _openSongSearch() async {
    final songs = _songs;
    if (songs.isEmpty) return;
    final selectedIndex = await showSearch<int?>(
      context: context,
      delegate: SongSearchDelegate(
        songs: songs,
        currentIndex: musicService.currentSongIndex,
        isPlaying: musicService.isPlaying,
      ),
    );
    if (selectedIndex == null) return;
    try {
      await musicService.playSongAt(selectedIndex);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('HenkMusic'),
        actions: [
          IconButton(
            onPressed: _songs.isEmpty ? null : _openSongSearch,
            icon: const Icon(Icons.search_rounded),
            tooltip: '搜索歌曲',
          ),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/user'),
            icon: const Icon(Icons.person_rounded),
          ),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/settings'),
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildSongList(colorScheme)),
          if (_songs.isNotEmpty)
            BottomPlayerBar(
              song: _currentSong,
              isPlaying: musicService.isPlaying,
              currentPosition: musicService.currentPosition,
              onPlayPause: () => musicService.togglePlayPause(),
              onNext: _nextSong,
              onPrevious: _previousSong,
              onTap: _openPlayerPage,
            ),
        ],
      ),
    );
  }

  Widget _buildSongList(ColorScheme colorScheme) {
    final songs = _songs;
    if (songs.isEmpty) {
      return Center(
        child: musicService.scanning
            ? const CircularProgressIndicator()
            : Text(
                musicService.musicSource == MusicSource.kugou
                    ? '请选择个人中心里的酷狗歌单'
                    : '未找到歌曲',
              ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        final isCurrent = index == musicService.currentSongIndex;
        return _buildSongTile(song, isCurrent, colorScheme, index);
      },
    );
  }

  Widget _buildSongTile(
    Song song,
    bool isCurrent,
    ColorScheme colorScheme,
    int index,
  ) {
    Widget leading;
    if (song.coverPath.isNotEmpty) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(song.coverPath),
          width: 44,
          height: 44,
          cacheWidth: 96,
          cacheHeight: 96,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              _buildLeadingIcon(isCurrent, colorScheme, index),
        ),
      );
    } else if (song.coverUrl.isNotEmpty) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          song.coverUrl,
          width: 44,
          height: 44,
          cacheWidth: 96,
          cacheHeight: 96,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              _buildLeadingIcon(isCurrent, colorScheme, index),
        ),
      );
    } else {
      leading = _buildLeadingIcon(isCurrent, colorScheme, index);
    }

    return ListTile(
      onTap: () async {
        try {
          await musicService.playSongAt(index);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: leading,
      title: Text(
        song.title,
        style: TextStyle(
          color: isCurrent ? colorScheme.primary : colorScheme.onSurface,
          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        song.artist,
        style: TextStyle(
          color: colorScheme.onSurface.withOpacity(0.5),
          fontSize: 12,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        _formatDuration(song.duration),
        style: TextStyle(
          color: colorScheme.onSurface.withOpacity(0.4),
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildLeadingIcon(bool isCurrent, ColorScheme colorScheme, int index) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isCurrent
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: isCurrent && musicService.isPlaying
            ? Icon(
                Icons.equalizer_rounded,
                color: colorScheme.primary,
                size: 22,
              )
            : Text(
                '${index + 1}',
                style: TextStyle(
                  color: isCurrent
                      ? colorScheme.primary
                      : colorScheme.onSurface.withOpacity(0.5),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return '--:--';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class SongSearchDelegate extends SearchDelegate<int?> {
  SongSearchDelegate({
    required this.songs,
    required this.currentIndex,
    required this.isPlaying,
  }) : super(searchFieldLabel: '搜索当前歌单');

  final List<Song> songs;
  final int currentIndex;
  final bool isPlaying;

  @override
  TextStyle? get searchFieldStyle => const TextStyle(fontSize: 14);

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          onPressed: () => query = '',
          icon: const Icon(Icons.clear_rounded),
          tooltip: '清除',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
      tooltip: '返回',
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchList(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchList(context);
  }

  Widget _buildSearchList(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final results = _filteredSongs();
    if (results.isEmpty) {
      return Center(
        child: Text(
          query.trim().isEmpty ? '输入歌名或歌手搜索' : '没有找到匹配歌曲',
          style: TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final entry = results[index];
        final songIndex = entry.key;
        final song = entry.value;
        final isCurrent = songIndex == currentIndex;
        return ListTile(
          onTap: () => close(context, songIndex),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 2,
          ),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isCurrent
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: isCurrent && isPlaying
                  ? Icon(
                      Icons.equalizer_rounded,
                      color: colorScheme.primary,
                      size: 22,
                    )
                  : Text(
                      '${songIndex + 1}',
                      style: TextStyle(
                        color: isCurrent
                            ? colorScheme.primary
                            : colorScheme.onSurface.withValues(alpha: 0.5),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
          title: Text(
            song.title,
            style: TextStyle(
              color: isCurrent ? colorScheme.primary : colorScheme.onSurface,
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
          trailing: Text(
            _formatDuration(song.duration),
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.4),
              fontSize: 11,
            ),
          ),
        );
      },
    );
  }

  List<MapEntry<int, Song>> _filteredSongs() {
    final keyword = query.trim().toLowerCase();
    final indexedSongs = songs.indexed.map(
      (entry) => MapEntry(entry.$1, entry.$2),
    );
    if (keyword.isEmpty) return indexedSongs.toList();
    return indexedSongs.where((entry) {
      final song = entry.value;
      return song.title.toLowerCase().contains(keyword) ||
          song.artist.toLowerCase().contains(keyword) ||
          song.album.toLowerCase().contains(keyword);
    }).toList();
  }

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return '--:--';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
