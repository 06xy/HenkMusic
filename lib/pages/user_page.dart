import 'package:flutter/material.dart';

import '../main.dart';

class UserPage extends StatefulWidget {
  const UserPage({super.key});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  final _mobileController = TextEditingController();
  final _codeController = TextEditingController();
  bool _sendingCode = false;
  bool _loggingIn = false;

  @override
  void initState() {
    super.initState();
    musicService.addListener(_onServiceChanged);
    if (musicService.isKugouLoggedIn &&
        musicService.kugouPlaylists.isEmpty &&
        !musicService.kugouLoading) {
      musicService.refreshKugouProfile();
    }
  }

  @override
  void dispose() {
    musicService.removeListener(_onServiceChanged);
    _mobileController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _sendCode() async {
    final mobile = _mobileController.text.trim();
    if (mobile.isEmpty) {
      _showSnack('请输入手机号');
      return;
    }
    setState(() => _sendingCode = true);
    try {
      await musicService.sendKugouCaptcha(mobile);
      _showSnack('验证码已发送');
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  Future<void> _login() async {
    final mobile = _mobileController.text.trim();
    final code = _codeController.text.trim();
    if (mobile.isEmpty || code.isEmpty) {
      _showSnack('请输入手机号和验证码');
      return;
    }
    setState(() => _loggingIn = true);
    try {
      await musicService.loginKugou(mobile, code);
      _showSnack('登录成功');
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  Future<void> _openPlaylist(int index) async {
    final playlist = musicService.kugouPlaylists[index];
    try {
      await musicService.loadKugouPlaylist(playlist);
      if (!mounted) return;
      _showSnack('已载入 ${playlist.name}');
      Navigator.pop(context);
    } catch (e) {
      _showSnack(e.toString());
    }
  }

  Future<void> _downloadPlaylist(int index) async {
    final playlist = musicService.kugouPlaylists[index];
    try {
      await musicService.downloadKugouPlaylist(playlist);
      _showSnack('歌单下载完成');
    } catch (e) {
      _showSnack(e.toString());
    }
  }

  void _showDownloadProgress() {
    final progress = musicService.kugouDownloadProgress;
    if (progress == null) {
      _showSnack('暂无下载任务');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(progress.title),
        content: AnimatedBuilder(
          animation: musicService,
          builder: (context, _) {
            final current = musicService.kugouDownloadProgress ?? progress;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: current.ratio),
                const SizedBox(height: 12),
                Text('${current.completed}/${current.total} 首'),
                const SizedBox(height: 6),
                Text('当前：${current.current}'),
                const SizedBox(height: 6),
                Text('已跳过 ${current.skipped}，失败 ${current.failed}'),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('个人中心'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (musicService.isKugouLoggedIn)
            IconButton(
              onPressed: musicService.logoutKugou,
              icon: const Icon(Icons.logout_rounded),
              tooltip: '退出登录',
            ),
        ],
      ),
      body: musicService.isKugouLoggedIn
          ? _buildProfile(colorScheme)
          : _buildLogin(colorScheme),
    );
  }

  Widget _buildLogin(ColorScheme colorScheme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        Icon(Icons.music_note_rounded, size: 64, color: colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          '登录酷狗音乐',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _mobileController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: '手机号',
            prefixIcon: Icon(Icons.phone_rounded),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '验证码',
                  prefixIcon: Icon(Icons.password_rounded),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _sendingCode ? null : _sendCode,
              child: Text(_sendingCode ? '发送中' : '获取'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _loggingIn ? null : _login,
          icon: _loggingIn
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login_rounded),
          label: Text(_loggingIn ? '登录中' : '登录'),
        ),
        const SizedBox(height: 12),
        Text(
          '使用酷狗接口直接登录，不需要启动 kgapi 或 Node 服务。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.5),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildProfile(ColorScheme colorScheme) {
    final user = musicService.kugouUser;
    return RefreshIndicator(
      onRefresh: musicService.refreshKugouProfile,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          const SizedBox(height: 16),
          Center(child: _buildAvatar(user?.avatarUrl ?? '', colorScheme)),
          const SizedBox(height: 14),
          Center(
            child: Text(
              user?.nickname ?? '酷狗用户',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if ((user?.userId ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(
                'ID: ${user!.userId}',
                style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.5),
                  fontSize: 13,
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          Row(
            children: [
              Text(
                '我的歌单',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (musicService.kugouLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (musicService.kugouPlaylists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  musicService.kugouLoading ? '正在加载歌单...' : '暂无歌单',
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ),
            )
          else
            ...List.generate(
              musicService.kugouPlaylists.length,
              (index) => _buildPlaylistTile(index, colorScheme),
            ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String url, ColorScheme colorScheme) {
    if (url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: 88,
          height: 88,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultAvatar(colorScheme),
        ),
      );
    }
    return _buildDefaultAvatar(colorScheme);
  }

  Widget _buildDefaultAvatar(ColorScheme colorScheme) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.primaryContainer,
      ),
      child: Icon(Icons.person_rounded, color: colorScheme.primary, size: 46),
    );
  }

  Widget _buildPlaylistTile(int index, ColorScheme colorScheme) {
    final playlist = musicService.kugouPlaylists[index];
    final progress = musicService.kugouDownloadProgress;
    final isDownloading =
        progress?.playlistId == playlist.id && progress?.running == true;
    final progressRatio = isDownloading ? progress!.ratio : 0.0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        onTap: musicService.kugouLoading ? null : () => _openPlaylist(index),
        leading: _buildPlaylistCover(playlist.coverUrl, colorScheme),
        title: Text(
          playlist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          isDownloading
              ? '下载中 ${(progressRatio * 100).toStringAsFixed(0)}%'
              : '${playlist.songCount} 首歌曲',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: musicService.kugouLoading
                  ? null
                  : isDownloading
                  ? _showDownloadProgress
                  : () => _downloadPlaylist(index),
              icon: isDownloading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        value: progressRatio,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Icon(Icons.download_rounded),
              tooltip: isDownloading ? '查看下载进度' : '下载歌单',
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistCover(String url, ColorScheme colorScheme) {
    if (url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultPlaylistCover(colorScheme),
        ),
      );
    }
    return _buildDefaultPlaylistCover(colorScheme);
  }

  Widget _buildDefaultPlaylistCover(ColorScheme colorScheme) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.queue_music_rounded, color: colorScheme.primary),
    );
  }
}
