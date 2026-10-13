// ============================================================
// lib/pages/login_page.dart — 授权登录页（页面层）
// 原理：内嵌 WebView 打开百度 OAuth 授权页 → 用户输入百度账号
// 密码并点"同意" → 页面跳转后 URL 中带 access_token → 提取保存
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../services/baidu_pan_api.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _showWeb = false; // 是否已点登录按钮（点后显示 WebView）

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _showWeb ? AppBar(title: const Text('百度账号授权')) : null,
      body: _showWeb ? _buildWebView() : _buildWelcome(),
    );
  }

  /// 登录前的欢迎界面
  Widget _buildWelcome() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_circle_fill, size: 96, color: Color(0xFF2E7CF6)),
            const SizedBox(height: 16),
            const Text('网盘视频播放器',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('原画质 · 倍速 · 手势缩放 · 断点续播',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
            const SizedBox(height: 48),
            // 登录按钮：点击后打开百度授权页
            FilledButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('使用百度网盘账号登录'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 16)),
              onPressed: () => setState(() => _showWeb = true),
            ),
            const SizedBox(height: 16),
            Text(
              '支持同时登录多个账号，登录后可在「我的」页添加或切换',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  /// 内嵌授权 WebView
  Widget _buildWebView() {
    return InAppWebView(
      initialUrlRequest:
          URLRequest(url: WebUri(BaiduPanApi.buildOAuthUrl())),
      // 页面加载完成后检查 URL 是否已携带 token
      onLoadStop: (controller, _) async => _checkToken(controller),
      // 部分场景跳转不触发 onLoadStop，这里兜底监听访问记录
      onUpdateVisitedHistory: (controller, _) async =>
          _checkToken(controller),
    );
  }

  /// 从当前页面 URL（含 # 后的 fragment）提取 access_token
  Future<void> _checkToken(InAppWebViewController controller) async {
    // location.href 完整包含 #access_token=xxx 部分
    final href = await controller.evaluateJavascript(
        content: 'window.location.href');
    if (href is! String) return;
    final parsed = BaiduPanApi.parseTokenFromUrl(href);
    if (parsed == null) return;

    final (token, expires) = parsed;
    // 拿用户信息（昵称/头像），失败也有兜底
    final account = await BaiduPanApi.fetchUserInfo(token);
    if (account == null) {
      _toast('授权成功，但获取用户信息失败，请重试');
      return;
    }
    // 保存账号并设为当前使用账号 → RootPage 监听到变化自动进入主界面
    await authService.addAccount(account);
    if (mounted) {
      Navigator.of(context).maybePop(); // 从"我的"页添加账号时返回
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
