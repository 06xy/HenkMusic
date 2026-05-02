import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/paddings/pkcs7.dart';
import 'package:pointycastle/padded_block_cipher/padded_block_cipher_impl.dart';
import 'package:pointycastle/pointycastle.dart';

import '../models/song.dart';

class KugouUser {
  final String userId;
  final String nickname;
  final String avatarUrl;

  const KugouUser({
    required this.userId,
    required this.nickname,
    required this.avatarUrl,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'nickname': nickname,
    'avatarUrl': avatarUrl,
  };

  factory KugouUser.fromJson(Map<String, dynamic> json) {
    return KugouUser(
      userId: json['userId']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '酷狗用户',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
    );
  }
}

class KugouPlaylist {
  final String id;
  final String globalCollectionId;
  final String name;
  final int songCount;
  final String coverUrl;

  const KugouPlaylist({
    required this.id,
    this.globalCollectionId = '',
    required this.name,
    required this.songCount,
    required this.coverUrl,
  });

  bool get hasListId => id.isNotEmpty && id != globalCollectionId;
}

class KugouApiService {
  static const _liteAppid = 3116;
  static const _liteClientver = 11440;
  static const _androidSecret = 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA';
  static const _songUrlSalt = '185672dd44712f60bb1736df5a377e82';
  static const _defaultMid = 'undefined';
  static const _androidUserAgent =
      'Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi';
  static const _litePublicModulusBase64Url =
      'xAotDadlEfO7HMK706-9i-qDtNawW2wT64kgxT8a92ebMroNDtuEMkDvG4Nu_tPuJAc0wUwTmf1llNFq8i9SUl0U1y4BVcbcyGONT3u5TzoLH0wp-ZGXLyoWCiXrCp5yQza-f2m70xn_qxxt2EcLAh3ENPP6uon0oqAbM7290Is';

  final Map<String, String> _cookies;
  final _random = Random.secure();

  KugouApiService({Map<String, String>? cookies}) : _cookies = cookies ?? {} {
    _ensureRuntimeCookies();
  }

  Map<String, String> get cookies => Map.unmodifiable(_cookies);

  void restoreCookies(Map<String, String> cookies) {
    _cookies
      ..clear()
      ..addAll(cookies);
    _ensureRuntimeCookies();
  }

  void clearCookies() => _cookies.clear();

  Future<void> sendCaptcha(String mobile) async {
    await _request(
      url: '/v7/send_mobile_code',
      baseUrl: 'http://login.user.kugou.com',
      method: 'POST',
      data: {'businessid': 5, 'mobile': mobile, 'plat': 3},
      cookie: const {},
    );
  }

  Future<KugouUser> loginByCaptcha({
    required String mobile,
    required String code,
  }) async {
    _ensureRuntimeCookies();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final encryptedParams = _aesEncryptHex({'mobile': mobile, 'code': code});
    final maskedMobile = mobile.length >= 11
        ? '${mobile.substring(0, 2)}*****${mobile.substring(10, 11)}'
        : mobile;
    final t2 = _aesEncryptHex(
      '${_cookies['KUGOU_API_GUID']}|0f607264fc6318a92b9e13c65db7cd3c|${_cookies['KUGOU_API_MAC']}|${_cookies['KUGOU_API_DEV']}|$nowMs',
      key: 'fd14b35e3f81af3817a20ae7adae7020',
      iv: '17a20ae7adae7020',
    ).cipherTextBase64;
    final t1 = _aesEncryptHex(
      '|$nowMs',
      key: '5e4ef500e9597fe004bd09a46d8add98',
      iv: '04bd09a46d8add98',
    ).cipherTextBase64;
    final response = await _request(
      baseUrl: 'https://loginserviceretry.kugou.com',
      url: '/v7/login_by_verifycode',
      method: 'POST',
      data: {
        'plat': 1,
        'support_multi': 1,
        't1': t1,
        't2': t2,
        'clienttime_ms': nowMs,
        'mobile': maskedMobile,
        'key': _signParamsKey(nowMs),
        'pk': _rsaNoPaddingHex({
          'clienttime_ms': nowMs,
          'key': encryptedParams.key,
        }).toUpperCase(),
        'params': encryptedParams.cipherTextBase64,
        'dfid': _cookies['dfid'] ?? _randomString(24),
        'dev': _cookies['KUGOU_API_DEV'],
        'gitversion': '5f0b7c4',
      },
      headers: {
        'support-calm': '1',
        HttpHeaders.userAgentHeader: 'Android16-1070-11440-130-0-LOGIN-wifi',
      },
    );

    final body = response.body;
    if (_number(body['status']).toInt() != 1) {
      throw Exception(body['error'] ?? body['msg'] ?? '登录失败');
    }

    final data = _firstMap(body['data']) ?? {};
    if (data['secu_params'] != null) {
      try {
        final decoded = _aesDecrypt(
          data['secu_params'].toString(),
          encryptedParams.key,
        );
        if (decoded is Map) data.addAll(Map<String, dynamic>.from(decoded));
      } catch (_) {
        // The lite login path normally returns token fields directly.
      }
    }
    _rememberCookieValue('token', data['token'], maxAge: true);
    _rememberCookieValue('userid', data['userid'], maxAge: true);
    _rememberCookieValue('vip_type', data['vip_type'] ?? 0, maxAge: true);
    _rememberCookieValue('vip_token', data['vip_token'] ?? '', maxAge: true);

    return fetchUserDetail();
  }

  Future<KugouUser> fetchUserDetail() async {
    final token = _cookies['token'] ?? '';
    final userid = _cookies['userid'] ?? '0';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final response = await _request(
      url: '/v3/get_my_info',
      method: 'POST',
      params: {'plat': 1},
      data: {
        'visit_time': now,
        'usertype': 1,
        'p': _rsaNoPaddingHex({
          'token': token,
          'clienttime': now,
        }).toUpperCase(),
        'userid': int.tryParse(userid) ?? 0,
      },
      headers: {'x-router': 'usercenter.kugou.com'},
    );
    final data = _firstMap(response.body['data']) ?? response.body;
    final userId =
        data['userid'] ?? data['user_id'] ?? data['uid'] ?? _cookies['userid'];
    final nickname =
        data['nickname'] ??
        data['nick_name'] ??
        data['username'] ??
        data['user_name'] ??
        '酷狗用户';
    final avatar =
        data['pic'] ??
        data['picurl'] ??
        data['img'] ??
        data['avatar'] ??
        data['headimg'] ??
        data['head_img'] ??
        '';
    return KugouUser(
      userId: userId?.toString() ?? '',
      nickname: nickname.toString(),
      avatarUrl: _normalizeImageUrl(avatar.toString()),
    );
  }

  Future<List<KugouPlaylist>> fetchPlaylists() async {
    final playlists = <KugouPlaylist>[];
    final userid = _cookies['userid'] ?? '0';
    final token = _cookies['token'] ?? '';
    final response = await _request(
      url: '/v7/get_all_list',
      method: 'POST',
      params: {'plat': 1, 'userid': int.tryParse(userid) ?? 0, 'token': token},
      data: {
        'userid': userid,
        'token': token,
        'total_ver': 979,
        'type': 2,
        'page': 1,
        'pagesize': 100,
      },
      headers: {'x-router': 'cloudlist.service.kugou.com'},
    );
    final candidates = _findLists(response.body);
    for (final item in candidates) {
      final listId = item['listid'] ?? item['list_id'];
      final globalCollectionId =
          item['global_collection_id'] ?? item['specialid'] ?? item['id'];
      final id = listId ?? globalCollectionId;
      if (id == null) continue;
      final name =
          item['name'] ??
          item['listname'] ??
          item['list_name'] ??
          item['specialname'] ??
          '未命名歌单';
      final count = _number(
        item['count'] ?? item['song_count'] ?? item['total'] ?? 0,
      ).toInt();
      final cover =
          item['pic'] ??
          item['picurl'] ??
          item['img'] ??
          item['cover'] ??
          item['sizable_cover'] ??
          '';
      playlists.add(
        KugouPlaylist(
          id: id.toString(),
          globalCollectionId: globalCollectionId?.toString() ?? '',
          name: name.toString(),
          songCount: count,
          coverUrl: _normalizeImageUrl(cover.toString()),
        ),
      );
    }
    return playlists;
  }

  Future<List<Song>> fetchPlaylistSongs(String listId) async {
    return _fetchAllPlaylistSongs(
      (page, pageSize) => _fetchPlaylistSongsByListId(listId, page, pageSize),
    );
  }

  Future<List<Song>> fetchPlaylistSongsFor(KugouPlaylist playlist) async {
    final fallbackId = playlist.globalCollectionId.isNotEmpty
        ? playlist.globalCollectionId
        : playlist.id;
    if (!playlist.hasListId) {
      return _fetchAllPlaylistSongs(
        (page, pageSize) =>
            _fetchPlaylistSongsByGlobalId(fallbackId, page, pageSize),
      );
    }

    try {
      return await _fetchAllPlaylistSongs(
        (page, pageSize) =>
            _fetchPlaylistSongsByListId(playlist.id, page, pageSize),
      );
    } catch (e) {
      if (!_looksLikeCode(e, '30228')) rethrow;
      return _fetchAllPlaylistSongs(
        (page, pageSize) =>
            _fetchPlaylistSongsByGlobalId(fallbackId, page, pageSize),
      );
    }
  }

  Future<List<Song>> _fetchAllPlaylistSongs(
    Future<_KugouResponse> Function(int page, int pageSize) fetchPage,
  ) async {
    const pageSize = 100;
    final songs = <Song>[];
    for (var page = 1; page <= 30; page++) {
      final response = await fetchPage(page, pageSize);
      final pageSongs = _songsFromPlaylistResponse(response);
      songs.addAll(pageSongs);
      if (pageSongs.length < pageSize) break;
    }
    final seen = <String>{};
    return songs.where((song) => seen.add(song.hash)).toList();
  }

  Future<_KugouResponse> _fetchPlaylistSongsByListId(
    String listId,
    int page,
    int pageSize,
  ) {
    return _request(
      url: '/v4/get_list_all_file',
      method: 'POST',
      data: {
        'listid': listId,
        'userid': _cookies['userid'] ?? '0',
        'area_code': 1,
        'show_relate_goods': 0,
        'pagesize': pageSize,
        'allplatform': 1,
        'show_cover': 1,
        'type': 0,
        'token': _cookies['token'] ?? '',
        'page': page,
      },
      headers: {'x-router': 'cloudlist.service.kugou.com'},
    );
  }

  Future<_KugouResponse> _fetchPlaylistSongsByGlobalId(
    String globalCollectionId,
    int page,
    int pageSize,
  ) {
    return _request(
      url: '/v4/get_other_list_file',
      method: 'GET',
      params: {
        'plat': 1,
        'type': 1,
        'module': 'NONE',
        'page': page,
        'pagesize': pageSize,
        'global_collection_id': globalCollectionId,
      },
      headers: {'x-router': 'pubsongscdn.kugou.com'},
    );
  }

  List<Song> _songsFromPlaylistResponse(_KugouResponse response) {
    return _findLists(
      response.body,
    ).map(_songFromMap).where((song) => song.hash.isNotEmpty).toList();
  }

  Future<List<MapEntry<Duration, String>>> fetchLyrics(Song song) async {
    final keyword = '${song.title} ${song.artist}'.trim();
    final search = await _request(
      baseUrl: 'https://lyrics.kugou.com',
      url: '/v1/search',
      method: 'GET',
      params: {
        'album_audio_id': song.albumAudioId.isEmpty ? 0 : song.albumAudioId,
        'appid': _liteAppid,
        'clientver': _liteClientver,
        'duration': song.duration.inSeconds,
        'hash': song.hash,
        'keyword': keyword,
        'lrctxt': 1,
        'man': 'no',
      },
      cookie: const {},
      clearDefaultParams: true,
    );
    final candidates = _findLists(search.body);
    if (candidates.isEmpty) return const [];
    final first = candidates.first;
    final id = first['id'] ?? first['content_id'];
    final accessKey = first['accesskey'] ?? first['access_key'];
    if (id == null || accessKey == null) return const [];

    final lyric = await _request(
      baseUrl: 'https://lyrics.kugou.com',
      url: '/download',
      method: 'GET',
      params: {
        'ver': 1,
        'client': 'android',
        'id': id,
        'accesskey': accessKey,
        'fmt': 'lrc',
        'charset': 'utf8',
      },
      cookie: const {},
    );
    final content = lyric.body['content']?.toString() ?? '';
    if (content.isEmpty) return const [];
    final lrc = utf8.decode(base64.decode(content));
    return _parseLrc(lrc);
  }

  Future<String> resolveSongUrl(Song song) async {
    if (song.playUrl.isNotEmpty) return song.playUrl;
    final data = await _resolveSongUrlData(song, freePart: false);
    final url = _findPlayableUrl(data);
    if (url.isNotEmpty) return url;

    final freeData = await _resolveSongUrlData(song, freePart: true);
    final freeUrl = _findPlayableUrl(freeData);
    if (freeUrl.isNotEmpty) return freeUrl;
    throw Exception('未获取到播放地址，可能是版权或会员限制');
  }

  Future<dynamic> _resolveSongUrlData(
    Song song, {
    required bool freePart,
  }) async {
    final response = await _request(
      url: '/v5/url',
      method: 'GET',
      params: {
        'album_id': int.tryParse(song.albumId) ?? 0,
        'area_code': 1,
        'hash': song.hash.toLowerCase(),
        'ssa_flag': 'is_fromtrack',
        'version': 11430,
        'page_id': 967177915,
        'quality': 128,
        'album_audio_id': int.tryParse(song.albumAudioId) ?? 0,
        'behavior': 'play',
        'pid': 411,
        'cmd': 26,
        'pidversion': 3001,
        'IsFreePart': freePart ? 1 : 0,
        'ppage_id': '356753938,823673182,967485191',
        'cdnBackup': 1,
        'module': '',
        'clientver': 11430,
      },
      headers: {'x-router': 'trackercdn.kugou.com'},
      encryptKey: true,
      cookie: {'dfid': _randomString(24), ..._cookies},
    );
    return response.body['data'] ?? response.body;
  }

  String _findPlayableUrl(dynamic node) {
    if (node is String) {
      if (node.startsWith('http://') || node.startsWith('https://')) {
        return node;
      }
      return '';
    }
    if (node is List) {
      for (final item in node) {
        final url = _findPlayableUrl(item);
        if (url.isNotEmpty) return url;
      }
      return '';
    }
    if (node is Map) {
      for (final key in const [
        'url',
        'play_url',
        'backup_url',
        'p2p_url',
        'cdn',
        'trans_param',
      ]) {
        if (node[key] == null) continue;
        final url = _findPlayableUrl(node[key]);
        if (url.isNotEmpty) return url;
      }
      for (final value in node.values) {
        final url = _findPlayableUrl(value);
        if (url.isNotEmpty) return url;
      }
    }
    return '';
  }

  Future<File> downloadSong(Song song, String rootDir) async {
    final url = await resolveSongUrl(song);
    final musicDir = Directory(p.join(rootDir, 'music'));
    if (!await musicDir.exists()) await musicDir.create(recursive: true);
    final target = File(
      p.join(musicDir.path, _safeFileName('${song.title}-${song.artist}.mp3')),
    );
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('下载失败：HTTP ${response.statusCode}');
      }
      await response.pipe(target.openWrite());
      return target;
    } finally {
      client.close(force: true);
    }
  }

  Future<_KugouResponse> _request({
    required String url,
    required String method,
    String baseUrl = 'https://gateway.kugou.com',
    Map<String, dynamic> params = const {},
    Map<String, dynamic>? data,
    Map<String, String> headers = const {},
    Map<String, String>? cookie,
    bool encryptKey = false,
    bool clearDefaultParams = false,
    bool notSignature = false,
  }) async {
    _ensureRuntimeCookies();
    final requestCookies = cookie ?? _cookies;
    final dfid = requestCookies['dfid'] ?? '-';
    final mid = requestCookies['KUGOU_API_MID'] ?? _defaultMid;
    const uuid = '-';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final defaultParams = <String, dynamic>{
      'dfid': dfid,
      'mid': mid,
      'uuid': uuid,
      'appid': _liteAppid,
      'clientver': _liteClientver,
      'clienttime': now,
      if ((requestCookies['token'] ?? '').isNotEmpty)
        'token': requestCookies['token'],
      if ((requestCookies['userid'] ?? '').isNotEmpty &&
          requestCookies['userid'] != '0')
        'userid': requestCookies['userid'],
    };
    final mergedParams = <String, dynamic>{
      if (!clearDefaultParams) ...defaultParams,
      ...params,
    };
    if (encryptKey) {
      mergedParams['key'] = _songUrlKey(
        mergedParams['hash']?.toString() ?? '',
        mergedParams['mid']?.toString() ?? '',
        mergedParams['userid'],
        mergedParams['appid'],
      );
    }
    final bodyText = data == null ? '' : jsonEncode(data);
    if (!notSignature) {
      mergedParams.putIfAbsent(
        'signature',
        () => _signatureAndroid(mergedParams, bodyText),
      );
    }

    final uri = _buildUri(baseUrl, url, mergedParams);
    final client = HttpClient();
    try {
      final request = method.toUpperCase() == 'POST'
          ? await client.postUrl(uri)
          : await client.getUrl(uri);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(HttpHeaders.userAgentHeader, _androidUserAgent)
        ..set('dfid', dfid)
        ..set('mid', mid)
        ..set('clienttime', mergedParams['clienttime'].toString())
        ..set('kg-rc', '1')
        ..set('kg-thash', '5d816a0')
        ..set('kg-rec', '1')
        ..set('kg-rf', 'B9EDA08A64250DEFFBCADDEE00F8F25F');
      headers.forEach(request.headers.set);
      if (data != null) {
        request.headers.contentType = ContentType.json;
        request.write(bodyText);
      }
      final response = await request.close();
      _captureCookies(response);
      final text = await utf8.decoder.bind(response).join();
      final decoded = text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>;
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          decoded['status'] == 0 ||
          (decoded['error_code'] != null && decoded['error_code'] != 0)) {
        throw Exception(decoded['msg'] ?? decoded['error'] ?? text);
      }
      return _KugouResponse(decoded);
    } finally {
      client.close(force: true);
    }
  }

  void _captureCookies(HttpClientResponse response) {
    for (final cookie in response.cookies) {
      _cookies[cookie.name] = cookie.value;
    }
  }

  void _ensureRuntimeCookies() {
    final guid = _cookies['KUGOU_API_GUID'] ?? _md5(_randomGuid());
    _cookies.putIfAbsent('KUGOU_API_PLATFORM', () => 'lite');
    _cookies.putIfAbsent('KUGOU_API_GUID', () => guid);
    _cookies.putIfAbsent('KUGOU_API_MID', () => _calculateMid(guid));
    _cookies.putIfAbsent('KUGOU_API_DEV', () => _randomString(10));
    _cookies.putIfAbsent('KUGOU_API_MAC', () => '02:00:00:00:00:00');
  }

  void _rememberCookieValue(String key, dynamic value, {bool maxAge = false}) {
    if (value == null) return;
    _cookies[key] = value.toString();
  }

  Song _songFromMap(Map<String, dynamic> item) {
    final fileName =
        _deepValue(item, const [
          'filename',
          'audio_name',
          'songname',
          'song_name',
          'name',
          'file_name',
        ]) ??
        '';
    var title = fileName.toString();
    var artist =
        _deepValue(item, const [
          'singername',
          'author_name',
          'singer_name',
          'artist',
          'singer',
        ]) ??
        '未知歌手';
    final splitIndex = title.lastIndexOf(' - ');
    if (splitIndex > 0 && splitIndex < title.length - 3) {
      artist = title.substring(0, splitIndex).trim();
      title = title.substring(splitIndex + 3).trim();
    }
    title = _stripAudioExtension(title);
    return Song(
      title: title,
      artist: artist.toString(),
      album: (_deepValue(item, const ['album_name', 'albumname']) ?? '')
          .toString(),
      duration: Duration(
        seconds: _number(
          _deepValue(item, const ['duration', 'time_length', 'timelength']) ??
              0,
        ).toInt(),
      ),
      coverUrl: _normalizeImageUrl(
        (_deepValue(item, const [
                  'pic',
                  'picurl',
                  'img',
                  'cover',
                  'sizable_cover',
                  'album_sizable_cover',
                  'image',
                ]) ??
                '')
            .toString(),
      ),
      source: MusicSource.kugou,
      hash: (_deepValue(item, const ['hash', 'file_hash', 'FileHash']) ?? '')
          .toString(),
      albumId: (_deepValue(item, const ['album_id', 'albumid']) ?? '')
          .toString(),
      albumAudioId:
          (_deepValue(item, const ['album_audio_id', 'mixsongid']) ?? '')
              .toString(),
      audioId: (_deepValue(item, const ['audio_id', 'audioid', 'id']) ?? '')
          .toString(),
    );
  }

  String _signatureAndroid(Map<String, dynamic> params, String data) {
    final paramsString = params.keys.toList()..sort();
    final text = paramsString.map((key) {
      final value = params[key];
      return '$key=${value is Map || value is List ? jsonEncode(value) : value}';
    }).join();
    return _md5('$_androidSecret$text$data$_androidSecret');
  }

  String _signParamsKey(int data) {
    return _md5('$_liteAppid$_androidSecret$_liteClientver$data');
  }

  String _songUrlKey(String hash, String mid, dynamic userid, dynamic appid) {
    return _md5('$hash$_songUrlSalt${appid ?? _liteAppid}$mid${userid ?? 0}');
  }

  String _rsaNoPaddingHex(dynamic data) {
    final json = data is String ? data : jsonEncode(data);
    final input = Uint8List(128);
    final bytes = utf8.encode(json);
    input.setRange(0, min(bytes.length, input.length), bytes);
    final modulus = BigInt.parse(
      _base64UrlToHex(_litePublicModulusBase64Url),
      radix: 16,
    );
    final publicKey = RSAPublicKey(modulus, BigInt.from(65537));
    final engine = RSAEngine()
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
    return _bytesToHex(engine.process(input));
  }

  _PlaylistAesResult _aesEncryptHex(dynamic data, {String? key, String? iv}) {
    final plainText = data is String ? data : jsonEncode(data);
    final randomKey = key == null ? _randomString(16).toLowerCase() : '';
    final aesKey = key ?? _md5(randomKey).substring(0, 32);
    final aesIv = iv ?? aesKey.substring(aesKey.length - 16);
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
          ..init(
            true,
            PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
              ParametersWithIV<KeyParameter>(
                KeyParameter(Uint8List.fromList(utf8.encode(aesKey))),
                Uint8List.fromList(utf8.encode(aesIv)),
              ),
              null,
            ),
          );
    final encrypted = cipher.process(
      Uint8List.fromList(utf8.encode(plainText)),
    );
    return _PlaylistAesResult(randomKey, _bytesToHex(encrypted));
  }

  dynamic _aesDecrypt(String hexText, String tempKey) {
    final keySeed = tempKey.isEmpty ? _randomString(16).toLowerCase() : tempKey;
    final key = _md5(keySeed).substring(0, 32);
    final iv = key.substring(key.length - 16);
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
          ..init(
            false,
            PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
              ParametersWithIV<KeyParameter>(
                KeyParameter(Uint8List.fromList(utf8.encode(key))),
                Uint8List.fromList(utf8.encode(iv)),
              ),
              null,
            ),
          );
    final decrypted = utf8.decode(cipher.process(_hexToBytes(hexText)));
    try {
      return jsonDecode(decrypted);
    } catch (_) {
      return decrypted;
    }
  }

  String _randomString(int len) {
    const chars = '1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    return List.generate(
      len,
      (_) => chars[_random.nextInt(chars.length)],
    ).join();
  }

  String _randomGuid() {
    String part() => _random.nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    return '${part()}${part()}-${part()}-${part()}-${part()}-${part()}${part()}${part()}';
  }

  String _calculateMid(String value) =>
      BigInt.parse(_md5(value), radix: 16).toString();

  String _md5(String value) => md5.convert(utf8.encode(value)).toString();

  Uri _buildUri(String baseUrl, String path, Map<String, dynamic> params) {
    final base = Uri.parse(baseUrl);
    final query = params.entries
        .where((entry) => entry.value != null)
        .map((entry) {
          final value = entry.value is Map || entry.value is List
              ? jsonEncode(entry.value)
              : entry.value.toString();
          return '${_axiosEncode(entry.key)}=${_axiosEncode(value)}';
        })
        .join('&');
    return base.replace(path: path, query: query.isEmpty ? null : query);
  }

  String _axiosEncode(String value) {
    return Uri.encodeComponent(value)
        .replaceAll('%3A', ':')
        .replaceAll('%24', r'$')
        .replaceAll('%2C', ',')
        .replaceAll('%20', '+')
        .replaceAll('%5B', '[')
        .replaceAll('%5D', ']')
        .replaceAll('%3a', ':')
        .replaceAll('%2c', ',')
        .replaceAll('%5b', '[')
        .replaceAll('%5d', ']');
  }

  List<Map<String, dynamic>> _findLists(dynamic value) {
    final result = <Map<String, dynamic>>[];
    void walk(dynamic node) {
      if (node is List) {
        final maps = node.whereType<Map>().toList();
        if (maps.isNotEmpty) {
          result.addAll(maps.map((item) => Map<String, dynamic>.from(item)));
          return;
        }
      }
      if (node is Map) {
        for (final key in const [
          'info',
          'list',
          'lists',
          'data',
          'songs',
          'items',
          'candidates',
        ]) {
          if (node[key] != null) walk(node[key]);
        }
      }
    }

    walk(value);
    return result;
  }

  Map<String, dynamic>? _firstMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return null;
  }

  dynamic _deepValue(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final direct = map[key];
      if (direct != null && direct.toString().isNotEmpty) return direct;
    }
    for (final value in map.values) {
      if (value is Map) {
        final nested = _deepValue(Map<String, dynamic>.from(value), keys);
        if (nested != null && nested.toString().isNotEmpty) return nested;
      } else if (value is List) {
        for (final item in value) {
          if (item is Map) {
            final nested = _deepValue(Map<String, dynamic>.from(item), keys);
            if (nested != null && nested.toString().isNotEmpty) return nested;
          }
        }
      }
    }
    return null;
  }

  num _number(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<MapEntry<Duration, String>> _parseLrc(String content) {
    final lines = content.split('\n');
    final result = <MapEntry<Duration, String>>[];
    final tagReg = RegExp(r'^\[(\d{2}):(\d{2})\.?(\d{0,3})\](.*)');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final match = tagReg.firstMatch(trimmed);
      if (match == null) continue;
      final min = int.parse(match.group(1)!);
      final sec = int.parse(match.group(2)!);
      final msStr = match.group(3) ?? '';
      final ms = msStr.isEmpty ? 0 : int.parse(msStr.padRight(3, '0'));
      result.add(
        MapEntry(
          Duration(minutes: min, seconds: sec, milliseconds: ms),
          match.group(4) ?? '',
        ),
      );
    }
    result.sort((a, b) => a.key.compareTo(b.key));
    return result;
  }

  String _normalizeImageUrl(String url) {
    if (url.isEmpty) return '';
    var normalized = url.replaceAll('{size}', '400');
    if (normalized.startsWith('//')) return 'https:$normalized';
    return normalized;
  }

  String _safeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  String _stripAudioExtension(String name) {
    return name.replaceFirst(
      RegExp(r'\.(mp3|flac|wav|aac|ogg|wma|m4a)$', caseSensitive: false),
      '',
    );
  }

  bool _looksLikeCode(Object error, String code) {
    return error.toString().contains(code);
  }

  String _base64UrlToHex(String value) {
    final normalized = base64Url.normalize(value);
    return _bytesToHex(base64Url.decode(normalized));
  }

  Uint8List _hexToBytes(String hex) {
    final output = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < output.length; i++) {
      output[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return output;
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

class _KugouResponse {
  final Map<String, dynamic> body;

  const _KugouResponse(this.body);
}

class _PlaylistAesResult {
  final String key;
  final String cipherTextBase64;

  const _PlaylistAesResult(this.key, this.cipherTextBase64);
}
