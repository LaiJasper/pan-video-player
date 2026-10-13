// ============================================================
// lib/pages/home_page.dart — 网盘首页：文件浏览 + 搜索（页面层）
// 功能：文件夹逐级导航、视频文件筛选、全盘关键词搜索、下拉刷新
// ============================================================
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/baidu_pan_api.dart';
import 'player_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _dir = '/';              // 当前目录路径
  final List<String> _stack = [];  // 目录导航栈（用于"返回上一级"）
  List<PanFile> _files = [];       // 当前显示的文件列表
  bool _loading = true;
  String? _error;
  bool _searchMode = false;        // 是否处于搜索模式

  @override
  void initState() {
    super.initState();
    // 监听账号变化：切换账号后回到根目录重新加载
    authService.addListener(_onAccountChanged);
    _reload();
  }

  @override
  void dispose() {
    authService.removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    _stack.clear();
    _dir = '/';
    _searchMode = false;
    _reload();
  }

  String get _token => authService.active?.accessToken ?? '';

  /// 加载文件列表（try-catch 保证网请求失败不崩页面）
  Future<void> _reload() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await BaiduPanApi.listFiles(_token, _dir);
      // 排序：文件夹在前、文件按名称在后
      list.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.compareTo(b.name);
      });
      _files = list;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _files = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  /// 全盘搜索
  Future<void> _doSearch(String keyword) async {
    if (keyword.trim().isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final list = await BaiduPanApi.searchFiles(_token, keyword.trim());
      // 只保留视频和文件夹，搜索结果里只展示视频
      _files = list.where((f) => !f.isDir).where(isVideoFile).toList();
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _files = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  /// 进入文件夹
  void _enterDir(PanFile dir) {
    _stack.add(_dir);
    _dir = dir.path;
    _reload();
  }

  /// 返回上一级
  void _goUp() {
    if (_searchMode) { // 搜索模式：先退出搜索回目录
      setState(() { _searchMode = false; });
      _reload();
      return;
    }
    if (_stack.isEmpty) return;
    _dir = _stack.removeLast();
    _reload();
  }

  /// 点击视频 → 打开播放页
  void _openVideo(PanFile file) {
    final account = authService.active;
    if (account == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(
        account: account,
        filePath: file.path,
        fileName: file.name,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final canUp = _stack.isNotEmpty || _searchMode;
    return Scaffold(
      appBar: AppBar(
        // 左上角"返回上一级"（根目录时隐藏）
        leading: canUp
            ? IconButton(icon: const Icon(Icons.arrow_upward), onPressed: _goUp)
            : null,
        title: _searchMode ? _buildSearchField() : Text(_dirName),
        actions: [
          // 搜索按钮：进入/退出搜索模式
          IconButton(
            icon: Icon(_searchMode ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _searchMode = !_searchMode);
              if (!_searchMode) _reload();
            },
          ),
          // 刷新按钮
          IconButton(icon: const Icon(Icons.refresh), onPressed: _reload),
        ],
      ),
      body: _buildBody(),
    );
  }

  /// AppBar 上显示的当前目录名
  String get _dirName {
    if (_searchMode) return '';
    if (_dir == '/') return '全部文件';
    return _dir.split('/').last;
  }

  Widget _buildSearchField() {
    return TextField(
      autofocus: true,
      decoration: const InputDecoration(
        hintText: '搜索网盘中的视频',
        border: InputBorder.none,
      ),
      onSubmitted: _doSearch,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _reload, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_files.isEmpty) {
      return Center(
        child: Text(_searchMode ? '没有找到相关视频' : '此目录为空',
            style: TextStyle(color: Colors.grey.shade500)),
      );
    }
    // 下拉刷新
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _files.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final f = _files[i];
          if (f.isDir) {
            // ── 文件夹：可点击进入下一级 ──
            return ListTile(
              leading: const Icon(Icons.folder, color: Color(0xFF2E7CF6)),
              title: Text(f.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _enterDir(f),
            );
          }
          final video = isVideoFile(f);
          // ── 文件：视频可点开播放，非视频置灰不可点 ──
          return ListTile(
            leading: Icon(
              video ? Icons.movie : Icons.insert_drive_file,
              color: video ? Colors.orangeAccent : Colors.grey,
            ),
            title: Text(f.name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: video ? null : Colors.grey)),
            subtitle: video && f.sizeText.isNotEmpty
                ? Text(f.sizeText, style: const TextStyle(fontSize: 12))
                : null,
            enabled: video,
            onTap: video ? () => _openVideo(f) : null,
          );
        },
      ),
    );
  }
}
