// ============================================================
// lib/app.dart — App 根组件（页面层）
// 职责：主题、登录态判断、底部导航（首页 / 我的）
// ============================================================
import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/mine_page.dart';
import 'services/auth_service.dart';

class PanVideoApp extends StatelessWidget {
  const PanVideoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '网盘视频',
      debugShowCheckedModeBanner: false,
      // 深色播放器风格主题，界面简洁
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7CF6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const RootPage(),
    );
  }
}

/// 根页面：根据登录状态显示「登录页」或「主界面」
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    // 启动时加载本地已保存的账号
    authService.load();
  }

  @override
  Widget build(BuildContext context) {
    // 监听账号变化：登录成功 / 切换账号 / 退出登录 → 自动刷新界面
    return AnimatedBuilder(
      animation: authService,
      builder: (context, _) {
        // 还在读取本地数据 → 显示启动画面
        if (!authService.loaded) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        // 一个账号都没有 → 登录页
        if (authService.accounts.isEmpty) {
          return const LoginPage();
        }
        // 已登录 → 主界面（首页 + 我的）
        return Scaffold(
          body: IndexedStack(
            index: _tabIndex,
            children: const [HomePage(), MinePage()],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tabIndex,
            onDestinationSelected: (i) => setState(() => _tabIndex = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder),
                  label: '首页'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: '我的'),
            ],
          ),
        );
      },
    );
  }
}
