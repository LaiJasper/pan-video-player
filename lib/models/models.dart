// ============================================================
// lib/models/models.dart — 数据模型
// 页面层 / 业务层之间传递的"数据对象"定义
// ============================================================

/// 一个已登录的网盘账号
class PanAccount {
  final String id;          // 唯一标识（用百度 uid）
  final String name;        // 显示昵称
  final String avatarUrl;  // 头像
  final String accessToken; // OAuth 授权令牌（调用网盘 API 的凭证）
  final int expiresIn;      // 令牌有效时长（秒）
  final DateTime loginTime; // 登录时间

  PanAccount({
    required this.id,
    required this.name,
    this.avatarUrl = '',
    required this.accessToken,
    required this.expiresIn,
    required this.loginTime,
  });

  /// 序列化为 JSON（存本地用）
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatarUrl': avatarUrl,
        'accessToken': accessToken,
        'expiresIn': expiresIn,
        'loginTime': loginTime.millisecondsSinceEpoch,
      };

  /// 从 JSON 还原
  factory PanAccount.fromJson(Map<String, dynamic> json) => PanAccount(
        id: json['id'].toString(),
        name: json['name'] ?? '百度账号',
        avatarUrl: json['avatarUrl'] ?? '',
        accessToken: json['accessToken'] ?? '',
        expiresIn: (json['expiresIn'] as num?)?.toInt() ?? 0,
        loginTime:
            DateTime.fromMillisecondsSinceEpoch(json['loginTime'] ?? 0),
      );
}

/// 网盘里的一个文件/文件夹
class PanFile {
  final String fsId;       // 文件唯一 ID
  final String path;       // 绝对路径，如 /电影/xxx.mp4
  final String name;       // 文件名
  final bool isDir;        // 是否文件夹
  final int size;          // 文件大小（字节）
  final int category;      // 百度分类：1=视频 2=音频 3=图片 4=文档 5=应用 6=其他 7=种子
  final DateTime? modified;// 修改时间

  PanFile({
    required this.fsId,
    required this.path,
    required this.name,
    required this.isDir,
    this.size = 0,
    this.category = 0,
    this.modified,
  });

  factory PanFile.fromApi(Map<String, dynamic> json) {
    return PanFile(
      fsId: json['fs_id']?.toString() ?? '',
      path: json['path'] ?? '',
      name: json['server_filename'] ?? (json['path']?.split('/').last ?? ''),
      isDir: (json['isdir'] ?? 0) == 1,
      size: (json['size'] as num?)?.toInt() ?? 0,
      category: (json['category'] as num?)?.toInt() ?? 0,
      modified: json['server_mtime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['server_mtime'] as num)!.toInt() * 1000)
          : null,
    );
  }

  /// 是否视频文件（category==1 优先，扩展名兜底）
  bool get isVideo {
    if (isDir) return false;
    if (category == 1) return true;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    // 引用 AppConfig 会造成循环依赖，扩展名判断放在调用处（api 层）
    return false;
  }

  /// 人类可读的文件大小
  String get sizeText {
    if (size <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var v = size.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
  }
}

/// 已保存的播放进度（断点续播用）
class PlayProgress {
  final String key;      // 唯一键 = 账号ID|文件路径
  final int positionMs;  // 上次播放位置（毫秒）
  final int durationMs;  // 视频总时长（毫秒）

  PlayProgress({required this.key, required this.positionMs, required this.durationMs});
}
