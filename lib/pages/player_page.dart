// ============================================================
// lib/pages/player_page.dart — 播放页（核心页面）
// 功能：
//   1. 原画质播放：先调 API 拿原始文件下载直链(dlink)，
//      经内置本地代理流式播放 → 分辨率/码率与原文件一致
//   2. 手势缩放：双指捏合/张开缩放画面，放大后可拖动，一键复位
//   3. 倍速：0.5x ~ 3.0x 共 8 档
//   4. 断点续播：进入自动续播 + 每 5 秒保存进度
//   5. 横竖屏自适应 + 阶段提示 + 90秒超时保护
//   6. 本地流代理：mpv 不直接连百度，由 Dart 层带正确 UA 取流转发
//      （解决原生请求被百度拒绝/UA丢失/重定向等问题）
// ============================================================
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../config/app_config.dart';
import '../models/models.dart';
import '../services/baidu_pan_api.dart';
import '../services/progress_service.dart';

class PlayerPage extends StatefulWidget {
  final PanAccount account; // 用于取 token 和标记进度归属
  final String filePath;    // 视频在网盘中的绝对路径
  final String fileName;    // 显示用文件名

  const PlayerPage({
    super.key,
    required this.account,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player player;            // mpv 播放器实例
  late final VideoController videoController;
  final TransformationController _zoomCtrl = TransformationController();
  _LocalStreamProxy? _proxy;           // 本地流代理（取流关键）

  bool _preparing = true;   // 正在获取直链/打开视频
  String _status = '正在向百度申请原文件直链…'; // 阶段提示（诊断用）
  String? _prepError;
  double _rate = 1.0;      // 当前倍速
  bool _showControls = true;// 是否显示控制条
  Timer? _saveTimer;       // 进度自动保存定时器
  Timer? _hideTimer;       // 控制条自动隐藏定时器
  String _resumeTip = '';   // "已从上次位置继续播放"提示

  /// 该视频的进度唯一键（同账号同文件 → 同一份进度）
  late final String _progressKey;

  @override
  void initState() {
    super.initState();
    _progressKey =
        ProgressService.buildKey(widget.account.id, widget.filePath);
    // 播放页允许横竖屏自由切换；退出后恢复竖屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // 加大网络缓冲：限速账号下播放更不容易卡顿
    player = Player(
      configuration: PlayerConfiguration(bufferSize: 64 * 1024 * 1024),
    );
    videoController = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true, // 硬件解码，保证流畅不卡顿
      ),
    );
    _openVideo();
  }

  /// 步骤1：拿原文件直链 → 步骤2：起本地代理 → 步骤3：播放 → 步骤4：断点续播
  Future<void> _openVideo() async {
    try {
      // ── 阶段1：申请直链 ──
      setState(() => _status = '正在向百度申请原文件直链…');
      final dlink =
          await BaiduPanApi.getDownloadLink(widget.account.accessToken, widget.filePath);

      // ── 阶段2：启动本地代理（Dart 层带正确 UA 取流，转发给播放器）──
      setState(() => _status = '已获取直链，正在启动本地流代理…');
      await _proxy?.stop();
      final proxy = _LocalStreamProxy();
      _proxy = proxy;
      final localUri = await proxy.start(dlink);

      // ── 阶段3：播放器连本地代理（mpv→127.0.0.1，无 UA/重定向问题）──
      // 非会员账号直链被百度限速，连接+首次缓冲可能较慢 → 90秒超时保护。
      setState(() => _status = '正在通过本地代理加载原画视频流…\n（非会员账号下载限速，首次打开可能较慢）');
      try {
        await player.open(Media(localUri.toString()))
            .timeout(const Duration(seconds: 90));
      } on TimeoutException {
        throw Exception(
            '加载视频流超时（90秒）。常见原因：\n'
            '① 百度对该账号下载限速，原画文件取流很慢\n'
            '② 网络不稳定\n'
            '请点"重试"再试一次，或先换一个小体积视频验证。');
      }

      // ── 阶段4：断点续播：有历史进度（且超过30秒）就自动跳到上次位置 ──
      final saved = await ProgressService.get(_progressKey);
      if (saved != null && saved.positionMs > 30000) {
        await player.seek(Duration(milliseconds: saved.positionMs));
        _resumeTip = '已从上次位置继续播放（${_fmt(saved.positionMs)}）';
        Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _resumeTip = '');
        });
      }
      // 播放中每 5 秒自动保存一次进度
      _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());
      if (mounted) setState(() { _preparing = false; });
    } catch (e) {
      if (mounted) {
        setState(() { _prepError = e.toString().replaceAll('Exception: ', ''); });
      }
    }
  }

  /// 保存当前播放位置（退出页面时也调用）
  Future<void> _saveProgress() async {
    final pos = player.state.position;
    final dur = player.state.duration;
    if (pos.inMilliseconds > 0 && dur.inMilliseconds > 0) {
      await ProgressService.save(
          _progressKey, pos.inMilliseconds, dur.inMilliseconds);
    }
  }

  /// 设置倍速（0.5x~3.0x 多档）
  void _setRate(double r) {
    player.setRate(r);
    setState(() => _rate = r);
  }

  /// 点击画面：显示/隐藏控制条；控制条 4 秒无操作自动隐藏
  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _showControls) setState(() => _showControls = false);
      });
    }
  }

  /// 双击画面左右 1/3 区域：快退/快进 10 秒
  void _doubleTapSeek(Offset localPosition, Size size) {
    final isLeft = localPosition.dx < size.width / 3;
    final isRight = localPosition.dx > size.width * 2 / 3;
    final pos = player.state.position;
    if (isLeft) {
      player.seek(pos - const Duration(seconds: 10));
    } else if (isRight) {
      player.seek(pos + const Duration(seconds: 10));
    }
  }

  /// 复位画面缩放
  void _resetZoom() => _zoomCtrl.value = Matrix4.identity();

  String _fmt(int ms) {
    final s = ms ~/ 1000;
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _hideTimer?.cancel();
    _saveProgress();       // 退出播放页：最后保存一次进度（断点续播关键）
    _proxy?.stop();        // 关闭本地代理
    player.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _preparing
          ? _buildPreparing()
          : _prepError != null
              ? _buildError()
              : _buildPlayer(),
    );
  }

  /// 加载中：显示当前阶段（便于判断卡在哪一步）
  Widget _buildPreparing() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(color: Colors.white),
        const SizedBox(height: 16),
        Text(_status,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ]),
    );
  }

  /// 打开失败：显示原因 + 重试
  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          Text(_prepError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              setState(() { _prepError = null; _preparing = true; });
              _openVideo();
            },
            child: const Text('重试'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('返回', style: TextStyle(color: Colors.white54)),
          ),
        ]),
      ),
    );
  }

  /// 播放主体：视频画面 + 手势缩放 + 控制条
  Widget _buildPlayer() {
    return Stack(
      children: [
        // ── 视频画面（InteractiveViewer 实现：双指缩放 + 放大后拖动）──
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: _zoomCtrl,
            maxScale: 5.0,   // 最大放大 5 倍，用于查看画面细节
            minScale: 1.0,
            panEnabled: true,
            child: GestureDetector(
              // 单击：呼出/隐藏控制条；双击两侧：快进快退
              onTap: _toggleControls,
              onDoubleTapDown: (d) =>
                  _doubleTapSeek(d.globalPosition, MediaQuery.of(context).size),
              child: Video(controller: videoController),
            ),
          ),
        ),
        // ── 断点续播提示 ──
        if (_resumeTip.isNotEmpty)
          Positioned(
            top: 56, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(_resumeTip,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ),
          ),
        // ── 控制条（顶部标题栏 + 底部播放控制栏）──
        AnimatedOpacity(
          opacity: _showControls ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !_showControls,
            child: Column(
              children: [
                _buildTopBar(),
                const Spacer(),
                _buildBottomBar(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 顶部栏：返回、文件名、缩放复位、横竖屏切换
  Widget _buildTopBar() {
    return Container(
      color: Colors.black45,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top, // 避开状态栏
        left: 4, right: 4,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(widget.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontSize: 16)),
          ),
          // 复位画面缩放
          IconButton(
            icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
            tooltip: '复位画面缩放',
            onPressed: _resetZoom,
          ),
          // 横竖屏切换
          IconButton(
            icon: const Icon(Icons.screen_rotation, color: Colors.white),
            tooltip: '横竖屏切换',
            onPressed: () {
              final isLand =
                  MediaQuery.of(context).orientation == Orientation.landscape;
              SystemChrome.setPreferredOrientations([
                isLand ? DeviceOrientation.portraitUp : DeviceOrientation.landscapeLeft,
              ]);
              // 解除锁定，恢复自适应（1秒后）
              Timer(const Duration(seconds: 1), () {
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.portraitUp,
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                ]);
              });
            },
          ),
        ],
      ),
    );
  }

  /// 底部栏：播放/暂停、进度条、时间、倍速按钮
  Widget _buildBottomBar() {
    return Container(
      color: Colors.black45,
      padding: EdgeInsets.only(
        left: 8, right: 8,
        bottom: MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条：实时显示 + 拖动跳转（StreamBuilder 监听播放位置流）
          StreamBuilder<Duration>(
            stream: player.stream.position,
            builder: (context, snap) {
              final pos = snap.data ?? Duration.zero;
              final dur = player.state.duration;
              return Row(
                children: [
                  Text(_fmt(pos.inMilliseconds),
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: dur.inMilliseconds.toDouble(),
                      value: pos.inMilliseconds
                          .clamp(0, dur.inMilliseconds)
                          .toDouble(),
                      onChanged: (v) {}, // 拖动中不实时 seek（避免卡顿）
                      onChangeEnd: (v) =>
                          player.seek(Duration(milliseconds: v.toInt())),
                    ),
                  ),
                  Text(_fmt(dur.inMilliseconds),
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 快退10秒
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white),
                onPressed: () => player.seek(
                    player.state.position - const Duration(seconds: 10)),
              ),
              // 播放/暂停
              StreamBuilder<bool>(
                stream: player.stream.playing,
                builder: (context, snap) {
                  final playing = snap.data ?? false;
                  return IconButton(
                    iconSize: 40,
                    icon: Icon(
                      playing ? Icons.pause_circle : Icons.play_circle,
                      color: Colors.white,
                    ),
                    onPressed: player.playOrPause,
                  );
                },
              ),
              // 快进10秒
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white),
                onPressed: () => player.seek(
                    player.state.position + const Duration(seconds: 10)),
              ),
              const SizedBox(width: 16),
              // 倍速按钮：点击弹出倍速选择面板
              TextButton(
                onPressed: _showSpeedSheet,
                child: Text('${_rate.toStringAsFixed(_rate == _rate.truncateToDouble() ? 1 : 2)}x',
                    style: const TextStyle(
                        color: Colors.orangeAccent, fontSize: 16)),
              ),
              const SizedBox(width: 8),
              // 从头播放（配合断点续播使用）
              TextButton(
                onPressed: () {
                  player.seek(Duration.zero);
                  _setRate(_rate);
                },
                child: const Text('从头播',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 倍速选择面板（底部弹层）：0.5x ~ 3.0x 共 8 档
  void _showSpeedSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('播放倍速',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12, runSpacing: 12,
              children: AppConfig.speedOptions.map((r) {
                final selected = r == _rate;
                return ChoiceChip(
                  label: Text('${r}x'),
                  selected: selected,
                  labelStyle: TextStyle(
                      color: selected ? Colors.black : Colors.white,
                      fontSize: 15),
                  selectedColor: Colors.orangeAccent,
                  backgroundColor: Colors.white12,
                  onSelected: (_) {
                    _setRate(r);
                    Navigator.of(context).pop();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 本地流代理（取流核心，私有实现）
// 原理：mpv → http://127.0.0.1:随机端口/stream?url=dlink
//       代理收到请求后用 dio（UA=pan.baidu.com）去取 dlink，
//       把响应字节原样转发给 mpv（含 Range 断点请求，支持拖进度条）。
// 好处：UA 与重定向全部由 Dart 层可靠处理，彻底绕开原生请求被拒。
// ============================================================
class _LocalStreamProxy {
  HttpServer? _server;
  final Dio _dio = Dio(BaseOptions(
    // 不设 receive 超时：视频流可能长时间持续传输
    connectTimeout: const Duration(seconds: 15),
    headers: {'User-Agent': 'pan.baidu.com'},
  ));

  /// 启动代理，返回供播放器使用的本地地址
  Future<Uri> start(String dlink) async {
    final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = srv;
    srv.listen((req) => _handle(req, dlink), onError: (_) {});
    return Uri.parse('http://127.0.0.1:${srv.port}/stream')
        .replace(queryParameters: {'url': dlink});
  }

  Future<void> _handle(HttpRequest req, String dlink) async {
    if (req.method != 'GET') {
      req.response.statusCode = 405;
      await req.response.close();
      return;
    }
    try {
      // 透传播放器的 Range 请求（拖进度条时 mpv 会带 Range 重新连接）
      final range = req.headers.value(HttpHeaders.rangeHeader);
      final res = await _dio.get<ResponseBody>(
        dlink,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'User-Agent': 'pan.baidu.com',
            if (range != null) 'Range': range,
          },
        ),
      );
      final body = res.data!;
      req.response.statusCode = res.statusCode ?? 200;
      res.headers.forEach((name, values) {
        // transfer-encoding 由本地服务器自行管理，透传会冲突
        if (name.toLowerCase() == 'transfer-encoding') return;
        req.response.headers.set(name, values);
      });
      // 把字节流转发给播放器；播放器中断连接（seek/退出）时静默处理
      await req.response.addStream(body.stream);
      await req.response.close();
    } catch (_) {
      // 播放器主动断开/取流异常：静默关闭本次连接
      try {
        req.response.close();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
