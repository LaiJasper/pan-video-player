// ============================================================
// lib/pages/mine_page.dart — 我的：多账号管理 + 设置（页面层）
// 功能：查看已登录账号列表、切换当前账号、添加账号、退出登录、
//       清除播放进度记录
// ============================================================
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/progress_service.dart';
import 'login_page.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: authService,
      builder: (context, _) {
        final accounts = authService.accounts;
        return Scaffold(
          appBar: AppBar(title: const Text('我的')),
          body: ListView(
            children: [
              // ── 账号管理区 ──
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('已登录账号（点击切换为当前使用账号）',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
              // 已登录账号卡片列表
              ...accounts.map((acc) {
                final isActive = acc.id == authService.active?.id;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF2E7CF6),
                    child: Text(acc.name.isNotEmpty ? acc.name[0] : '百',
                        style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(acc.name),
                  subtitle: Text(isActive ? '当前使用中' : '点击切换到此账号'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isActive)
                        const Icon(Icons.check_circle,
                            color: Color(0xFF2E7CF6)),
                      // 退出登录（删除该账号）
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.grey),
                        tooltip: '退出登录',
                        onPressed: () =>
                            _confirmLogout(acc.name, acc.id),
                      ),
                    ],
                  ),
                  onTap: () => authService.switchAccount(acc.id),
                );
              }),
              // 添加账号按钮 → 进入登录页（可继续加第二个账号）
              ListTile(
                leading: const Icon(Icons.add_circle_outline,
                    color: Color(0xFF2E7CF6)),
                title: const Text('添加百度网盘账号'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                ),
              ),
              const Divider(height: 32),
              // ── 设置区 ──
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text('设置',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
              // 清除全部播放进度（断点续播记录）
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('清除播放进度记录'),
                subtitle: const Text('清除后所有视频将从开头播放'),
                onTap: _confirmClearProgress,
              ),
              // 关于
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('关于'),
                subtitle: Text('网盘视频播放器 V1.0 · 基于官方开放接口'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 退出登录：二次确认，防止误点
  void _confirmLogout(String name, String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: Text('确定要退出「$name」吗？\n该账号的播放进度记录仍会保留。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消')),
          FilledButton(
              onPressed: () {
                authService.removeAccount(id);
                Navigator.of(context).pop();
              },
              child: const Text('退出')),
        ],
      ),
    );
  }

  /// 清除播放进度：二次确认
  void _confirmClearProgress() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除播放进度'),
        content: const Text('将删除所有视频的断点续播记录，确定吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消')),
          FilledButton(
              onPressed: () async {
                await ProgressService.clearAll();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('清除')),
        ],
      ),
    );
  }
}
