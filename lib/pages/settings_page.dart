import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../main.dart';
import '../models/song.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _scanning = false;

  Future<bool> _requestPermission() async {
    if (Platform.isAndroid) {
      await Permission.notification.request();

      if (await Permission.manageExternalStorage.isGranted) return true;
      if (await Permission.storage.isGranted) return true;

      final manageResult = await Permission.manageExternalStorage.request();
      if (manageResult.isGranted) return true;

      final storageResult = await Permission.storage.request();
      if (storageResult.isGranted) return true;

      final audioResult = await Permission.audio.request();
      if (audioResult.isGranted) return true;

      if (await Permission.manageExternalStorage.isPermanentlyDenied) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('需要存储权限'),
              content: const Text('请在设置中允许「管理所有文件」权限，用于扫描音乐文件。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    openAppSettings();
                  },
                  child: const Text('去设置'),
                ),
              ],
            ),
          );
        }
        return false;
      }

      return storageResult.isGranted || audioResult.isGranted;
    }
    return true;
  }

  Future<void> _requestPermissionFromTile() async {
    final granted = await _requestPermission();
    final hasAllFiles =
        !Platform.isAndroid || await Permission.manageExternalStorage.isGranted;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted && hasAllFiles
              ? '权限已允许'
              : granted
              ? '已获得媒体权限；歌词文件建议开启「管理所有文件」'
              : '未获得存储权限',
        ),
      ),
    );
  }

  Future<void> _openPermissionSettings() async {
    await openAppSettings();
  }

  Future<void> _pickDirectory() async {
    final granted = await _requestPermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('需要存储权限才能扫描音乐文件')));
      }
      return;
    }

    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择音乐根目录',
    );
    if (result == null) return;

    try {
      await musicService.setRootDir(result);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('目录已保存，请点击手动扫描更新歌曲列表')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('扫描失败: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _scanNow() async {
    final granted = await _requestPermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('需要存储权限才能扫描音乐文件')));
      }
      return;
    }

    if (!mounted) return;
    if (musicService.rootDir == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择音乐根目录')));
      return;
    }

    setState(() => _scanning = true);
    try {
      await musicService.scanFiles();
      if (!mounted) return;
      final count = musicService.scannedCount;
      final error = musicService.lastError;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), duration: const Duration(seconds: 5)),
        );
      } else if (count == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未找到音频文件，请检查目录结构'),
            duration: Duration(seconds: 5),
          ),
        );
      } else {
        final lyricsHint = musicService.failedLyricsCount > 0
            ? '，${musicService.failedLyricsCount} 个歌词读取失败，请检查全部文件访问权限'
            : '，歌词 ${musicService.scannedLyricsCount} 个';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('扫描成功，共 $count 首歌曲$lyricsHint')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('扫描失败: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _clearDirectory() async {
    await musicService.clearRootDir();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已恢复默认歌曲列表')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rootDir = musicService.rootDir;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _buildVersionHeader(colorScheme),
          const SizedBox(height: 12),
          _buildSection('歌曲源设置', [
            _buildSourceTile(
              MusicSource.local,
              '本地文件夹',
              '扫描本地 music/、lyrics/、cover/ 目录',
              Icons.folder_rounded,
              colorScheme,
            ),
            const Divider(height: 1),
            _buildSourceTile(
              MusicSource.kugou,
              '酷狗音乐',
              '登录后从个人歌单播放在线歌曲',
              Icons.cloud_rounded,
              colorScheme,
            ),
          ], colorScheme),
          if (musicService.musicSource == MusicSource.local) ...[
            const SizedBox(height: 18),
            _buildSection('扫描设置', [
              _buildPermissionTile(colorScheme),
              const Divider(height: 1),
              _buildDirectoryTile(colorScheme, rootDir),
              const Divider(height: 1),
              _buildManualScanTile(colorScheme),
            ], colorScheme),
          ],
          const SizedBox(height: 18),
          _buildSection('播放设置', [_buildBoundaryTile(colorScheme)], colorScheme),
        ],
      ),
    );
  }

  Widget _buildVersionHeader(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        '版本 1.0.6+7',
        style: TextStyle(
          color: colorScheme.onSurface.withOpacity(0.45),
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildSourceTile(
    MusicSource source,
    String title,
    String subtitle,
    IconData icon,
    ColorScheme colorScheme,
  ) {
    return RadioListTile<MusicSource>(
      value: source,
      groupValue: musicService.musicSource,
      onChanged: (value) async {
        if (value == null) return;
        await musicService.setMusicSource(value);
        if (mounted) setState(() {});
      },
      secondary: Icon(icon, color: colorScheme.primary),
      title: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: colorScheme.onSurface.withOpacity(0.5),
          fontSize: 12,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildManualScanTile(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.manage_search_rounded, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '手动扫描',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  musicService.rootDir == null
                      ? '选择目录后可手动更新歌曲列表'
                      : '当前 ${musicService.scannedCount} 首歌曲',
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _scanning || musicService.scanning ? null : _scanNow,
            icon: _scanning || musicService.scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: Text(_scanning || musicService.scanning ? '扫描中' : '扫描'),
          ),
        ],
      ),
    );
  }

  Widget _buildBoundaryTile(ColorScheme colorScheme) {
    return Column(
      children: [
        RadioListTile<BoundaryAction>(
          value: BoundaryAction.keepPlaying,
          groupValue: musicService.boundaryAction,
          onChanged: (value) {
            if (value == null) return;
            musicService.setBoundaryAction(value);
            setState(() {});
          },
          secondary: Icon(
            Icons.notifications_none_rounded,
            color: colorScheme.primary,
          ),
          title: const Text('到列表边界时仅提示'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          visualDensity: VisualDensity.compact,
        ),
        const Divider(height: 1),
        RadioListTile<BoundaryAction>(
          value: BoundaryAction.restartCurrent,
          groupValue: musicService.boundaryAction,
          onChanged: (value) {
            if (value == null) return;
            musicService.setBoundaryAction(value);
            setState(() {});
          },
          secondary: Icon(Icons.replay_rounded, color: colorScheme.primary),
          title: const Text('到列表边界时重放当前歌曲'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _buildPermissionTile(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.admin_panel_settings_rounded, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '文件访问权限',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '用于读取本地歌曲、.lrc 歌词和封面',
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _requestPermissionFromTile,
            child: const Text('申请'),
          ),
          IconButton(
            onPressed: _openPermissionSettings,
            icon: const Icon(Icons.settings_applications_rounded),
            tooltip: '系统权限设置',
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryTile(ColorScheme colorScheme, String? rootDir) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '音乐目录',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '选择根目录后不会自动扫描，可在扫描设置中手动更新。目录结构：\n'
            '  music/   音频文件（歌名-作者.mp3）\n'
            '  lyrics/  歌词文件（歌名-作者.lrc）\n'
            '  cover/   封面图片（歌名-作者.png）',
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          if (rootDir != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.folder_rounded,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          rootDir,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.music_note_rounded,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'music/',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.lyrics_rounded,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'lyrics/',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.image_rounded,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'cover/',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _scanning ? null : _pickDirectory,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('选择目录'),
                ),
              ),
              if (rootDir != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _scanning ? null : _clearDirectory,
                  icon: const Icon(Icons.restore_rounded, size: 18),
                  label: const Text('恢复默认'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    String title,
    List<Widget> children,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              color: colorScheme.primary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}
