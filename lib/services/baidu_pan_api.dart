// ============================================================
// lib/services/baidu_pan_api.dart — 百度网盘官方开放平台 API 封装（网络层）
// 官方文档：https://pan.baidu.com/union/doc/
// 实现功能：OAuth登录地址、获取用户信息、文件列表、搜索、视频下载直链
//
// 关于"原画质播放"的原理：
//   网盘官方 App 在线播放 = 服务器转码压缩后的视频流（画质降低）
//   本 App = 调用官方接口拿到"原始文件的下载直链(dlink)"，
//            播放器直接流式读取原文件 → 分辨率/码率与原文件完全一致
// ============================================================
import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../models/models.dart';

class BaiduPanApi {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    // 百度网盘接口要求请求头 UA 固定为 pan.baidu.com
    headers: {'User-Agent': 'pan.baidu.com'},
  ));

  /// 组装 OAuth 授权页地址（登录页 WebView 打开这个 URL）
  static String buildOAuthUrl() {
    return 'https://openapi.baidu.com/oauth/2.0/authorize'
        '?response_type=token'
        '&client_id=${AppConfig.baiduAppKey}'
        '&redirect_uri=${Uri.encodeComponent(AppConfig.redirectUri)}'
        '&scope=${Uri.encodeComponent(AppConfig.scope)}'
        '&display=mobile'; // mobile=手机版授权页，界面更适合App内嵌
  }

  /// 从回调 URL 中解析 access_token（implicit 授权：token 在 URL 的 # 后面）
  /// 成功返回 (token, expiresIn)，失败返回 null
  static (String, int)? parseTokenFromUrl(String url) {
    final m = RegExp(r'access_token=([^&#]+)').firstMatch(url);
    if (m == null) return null;
    final token = m.group(1)!;
    final e = RegExp(r'expires_in=(\d+)').firstMatch(url);
    final expires = e != null ? int.tryParse(e.group(1)!) ?? 2592000 : 2592000;
    return (token, expires);
  }

  /// 获取登录用户信息（昵称、头像、uid）
  static Future<PanAccount?> fetchUserInfo(String accessToken) async {
    try {
      final r = await _dio.get(
        'https://openapi.baidu.com/rest/2.0/passport/users/getLoggedInUser',
        queryParameters: {'access_token': accessToken},
      );
      final d = r.data as Map<String, dynamic>;
      if (d['uid'] == null) return null;
      return PanAccount(
        id: d['uid'].toString(),
        name: (d['username'] ?? d['showname'] ?? '百度账号').toString(),
        avatarUrl: d['portrait'] != null
            ? 'https://himg.bdimg.com/sys/portraitn/item/${d['portrait']}'
            : '',
        accessToken: accessToken,
        expiresIn: 2592000,
        loginTime: DateTime.now(),
      );
    } catch (_) {
      // 拿不到用户信息也不阻塞登录，用兜底账号
      return PanAccount(
        id: 'bd_${DateTime.now().millisecondsSinceEpoch}',
        name: '百度账号',
        accessToken: accessToken,
        expiresIn: 2592000,
        loginTime: DateTime.now(),
      );
    }
  }

  /// 获取目录下的文件列表（文件浏览页核心接口）
  /// [dir] 目录绝对路径，如 '/' 或 '/电影'
  static Future<List<PanFile>> listFiles(String accessToken, String dir) async {
    final r = await _dio.get('https://pan.baidu.com/rest/2.0/xpan/file',
        queryParameters: {
          'method': 'list',
          'access_token': accessToken,
          'dir': dir,
          'order': 'name', // 按名称排序
          'web': 1,
        });
    _checkError(r.data);
    final list = (r.data['list'] as List?) ?? [];
    return list.map((e) => PanFile.fromApi(e as Map<String, dynamic>)).toList();
  }

  /// 全盘关键词搜索（文件浏览页搜索功能）
  static Future<List<PanFile>> searchFiles(String accessToken, String keyword) async {
    final r = await _dio.get('https://pan.baidu.com/rest/2.0/xpan/file',
        queryParameters: {
          'method': 'search',
          'access_token': accessToken,
          'key': keyword,
          'web': 1,
        });
    _checkError(r.data);
    final list = (r.data['list'] as List?) ?? [];
    return list.map((e) => PanFile.fromApi(e as Map<String, dynamic>)).toList();
  }

  /// 获取视频文件的"原始文件下载直链"（原画播放的核心）
  /// 返回的 dlink 是指向原始视频文件（未转码）的临时下载地址，
  /// 播放器带 User-Agent 头直接流式播放该地址即可原画质观看。
  /// ⚠️ dlink 有效期约 8 小时，且要求 UA = pan.baidu.com
  static Future<String> getDownloadLink(String accessToken, String path) async {
    final r = await _dio.get('https://pan.baidu.com/rest/2.0/xpan/file',
        queryParameters: {
          'method': 'file_download',
          'access_token': accessToken,
          'path': path,
        });
    _checkError(r.data);
    final dlink = r.data['dlink'] as String?;
    if (dlink == null || dlink.isEmpty) {
      throw Exception('未能获取下载直链（文件可能违规被封禁或非会员受限）');
    }
    return dlink;
  }

  /// 统一检查百度返回的错误码
  /// 常见：111=access_token过期（需重新登录）、-6=身份验证失败、31034=命中接口频控
  static void _checkError(dynamic data) {
    if (data is! Map) return;
    final errno = data['errno'];
    if (errno != null && errno != 0) {
      switch (errno) {
        case 111:
          throw Exception('登录凭证已过期，请到「我的」页重新登录该账号 (errno=111)');
        case -6:
          throw Exception('身份验证失败，请重新登录 (errno=-6)');
        case 31034:
          throw Exception('请求太频繁，请稍后再试 (errno=31034)');
        default:
          throw Exception('网盘接口错误：errno=$errno ${data['errmsg'] ?? ''}');
      }
    }
  }
}

/// 判断文件是否为视频（供文件浏览页使用）
bool isVideoFile(PanFile f) {
  if (f.isDir) return false;
  if (f.category == 1) return true;
  final lower = f.name.toLowerCase();
  return AppConfig.videoExtensions.any((ext) => lower.endsWith(ext));
}
