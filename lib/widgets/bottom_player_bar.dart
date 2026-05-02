import 'dart:io';
import 'package:flutter/material.dart';
import '../models/song.dart';

class BottomPlayerBar extends StatelessWidget {
  final Song song;
  final bool isPlaying;
  final Duration currentPosition;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onTap;

  const BottomPlayerBar({
    super.key,
    required this.song,
    required this.isPlaying,
    required this.currentPosition,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progress = song.duration.inMilliseconds > 0
        ? currentPosition.inMilliseconds / song.duration.inMilliseconds
        : 0.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                minHeight: 2.5,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    _buildCover(colorScheme),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artist,
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
                      onPressed: onPrevious,
                      icon: const Icon(Icons.skip_previous_rounded),
                      color: colorScheme.onSurface,
                      iconSize: 26,
                    ),
                    IconButton(
                      onPressed: onPlayPause,
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      color: colorScheme.primary,
                      iconSize: 30,
                    ),
                    IconButton(
                      onPressed: onNext,
                      icon: const Icon(Icons.skip_next_rounded),
                      color: colorScheme.onSurface,
                      iconSize: 26,
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

  Widget _buildCover(ColorScheme colorScheme) {
    if (song.coverPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(song.coverPath),
          width: 44,
          height: 44,
          cacheWidth: 96,
          cacheHeight: 96,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultCover(colorScheme),
        ),
      );
    }
    if (song.coverUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          song.coverUrl,
          width: 44,
          height: 44,
          cacheWidth: 96,
          cacheHeight: 96,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultCover(colorScheme),
        ),
      );
    }
    return _buildDefaultCover(colorScheme);
  }

  Widget _buildDefaultCover(ColorScheme colorScheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 44,
        height: 44,
        color: colorScheme.primaryContainer,
        child: Icon(
          Icons.music_note_rounded,
          color: colorScheme.primary,
          size: 24,
        ),
      ),
    );
  }
}
