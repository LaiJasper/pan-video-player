// ============================================================
// lib/services/progress_service.dart — 播放进度存储（本地存储层）
// 用 SQLite 保存每个视频的播放位置 → 实现"进度记忆 + 断点续播"
// ============================================================
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/models.dart';

class ProgressService {
  static Database? _db;

  /// 打开（或创建）本地数据库
  static Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'pan_player.db'),
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE progress (
          key TEXT PRIMARY KEY,        -- 账号ID|文件路径（同账号同文件唯一）
          position_ms INTEGER NOT NULL,-- 上次播放位置（毫秒）
          duration_ms INTEGER NOT NULL,-- 视频总时长（毫秒）
          updated_at INTEGER NOT NULL   -- 更新时间戳
        )
      '''),
    );
    return _db!;
  }

  /// 生成唯一键：同一账号的同一文件 → 同一份进度
  static String buildKey(String accountId, String filePath) => '$accountId|$filePath';

  /// 保存/更新播放进度（播放中每 5 秒调一次 + 退出播放页时调一次）
  static Future<void> save(String key, int positionMs, int durationMs) async {
    final database = await db;
    // 快进到接近结尾视为"已看完"，下次从头播
    if (durationMs > 0 && positionMs >= durationMs - 5000) {
      await database.delete('progress', where: 'key = ?', whereArgs: [key]);
      return;
    }
    await database.insert(
      'progress',
      {
        'key': key,
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 读取播放进度（进入播放页时调用，null=没看过）
  static Future<PlayProgress?> get(String key) async {
    final database = await db;
    final rows = await database.query('progress',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return PlayProgress(
      key: key,
      positionMs: rows.first['position_ms'] as int,
      durationMs: rows.first['duration_ms'] as int,
    );
  }

  /// 清空全部进度（设置页"清除播放记录"用）
  static Future<void> clearAll() async {
    final database = await db;
    await database.delete('progress');
  }
}
