// ============================================================
// lib/main.dart — App 入口
// 职责：初始化播放内核（media_kit），启动应用
// ============================================================
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart';

void main() {
  // Flutter 绑定初始化（使用插件前必须调用）
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化 media_kit 播放引擎（基于 mpv，视频解码的核心）
  MediaKit.ensureInitialized();
  runApp(const PanVideoApp());
}
