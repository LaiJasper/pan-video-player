// ============================================================
// lib/services/auth_service.dart — 多账号管理（业务逻辑层）
// 职责：账号的增/删/切换/持久化，全局通知页面刷新
// ============================================================
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// 全局单例：所有页面通过它读写"当前登录了哪些账号"
final AuthService authService = AuthService();

class AuthService extends ChangeNotifier {
  static const _kAccounts = 'pan_accounts_json';
  static const _kActiveId = 'pan_active_account_id';

  List<PanAccount> _accounts = [];
  String? _activeId;
  bool loaded = false; // 是否已完成首次本地数据加载

  List<PanAccount> get accounts => List.unmodifiable(_accounts);

  /// 当前活跃账号（网盘首页、播放都使用它的 token）
  PanAccount? get active {
    try {
      return _accounts.firstWhere((a) => a.id == _activeId);
    } catch (_) {
      return _accounts.isNotEmpty ? _accounts.first : null;
    }
  }

  /// App 启动时从本地读取已保存的账号
  Future<void> load() async {
    if (loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAccounts);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _accounts = list.map((e) => PanAccount.fromJson(e)).toList();
      } catch (_) {
        _accounts = [];
      }
    }
    _activeId = prefs.getString(_kActiveId);
    loaded = true;
    notifyListeners();
  }

  /// 登录成功后添加账号（若已存在则覆盖旧 token，等于"重新登录"）
  Future<void> addAccount(PanAccount acc) async {
    _accounts.removeWhere((a) => a.id == acc.id);
    _accounts.add(acc);
    _activeId = acc.id; // 新登录的账号自动设为当前使用账号
    await _save();
  }

  /// 切换当前账号
  Future<void> switchAccount(String id) async {
    if (_accounts.any((a) => a.id == id)) {
      _activeId = id;
      await _save();
    }
  }

  /// 删除（退出登录）某账号
  Future<void> removeAccount(String id) async {
    _accounts.removeWhere((a) => a.id == id);
    if (_activeId == id) {
      _activeId = _accounts.isNotEmpty ? _accounts.first.id : null;
    }
    await _save();
  }

  /// 持久化到本地（SharedPreferences，仅存于应用私有目录，卸载即清除）
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kAccounts, jsonEncode(_accounts.map((a) => a.toJson()).toList()));
    if (_activeId != null) {
      await prefs.setString(_kActiveId, _activeId!);
    } else {
      await prefs.remove(_kActiveId);
    }
    notifyListeners();
  }
}
