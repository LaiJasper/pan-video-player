# 网盘视频播放器（pan_video_player）

百度网盘视频原画播放 App：原画质流式播放（不转码降清）、0.5x~3.0x 八档倍速、双指手势缩放、断点续播、多账号管理。基于 Flutter + media_kit(mpv) + 百度网盘官方开放平台接口。

## 快速开始

- **云端打包（推荐，电脑无需装任何开发工具）**：把本项目推到 GitHub 私有仓库 → 在 Secrets 里配置 `BAIDU_APP_KEY` → Actions 页面点 "Run workflow" → 15 分钟后下载 APK。详见 `docs/打包指南.md` 顶部"方案 B"。
- **本地打包**：见下方 3 步与 `docs/打包指南.md` 方案 A。

## 本地打包（3 步）

### 第 1 步：生成项目骨架

本仓库提供 `lib/` 源码与 `pubspec.yaml`。Flutter 的 `android/` 平台目录需要用官方命令生成（一次性）：

```bash
# 假设已安装 Flutter SDK（见 docs/打包指南.md 第 1 节）
cd pan_video_player
flutter create . --org com.example --project-name pan_video_player
flutter pub get
```

`flutter create .` 只会补齐缺失的 `android/`、`ios/` 等平台目录，不会覆盖你已有的 `lib/` 和 `pubspec.yaml`。

### 第 2 步：填入百度开放平台密钥（必须）

打开 `lib/config/app_config.dart`，把 `baiduAppKey`、`baiduSecretKey` 换成你在百度网盘开放平台（https://pan.baidu.com/union）创建应用后获得的真实 Key。**没有这一步无法登录。** 申请流程见 `docs/打包指南.md` 第 2 节。

### 第 3 步：配置 Android 权限与横屏

编辑 `android/app/src/main/AndroidManifest.xml`，在 `<manifest>` 内、`<application>` 标签外添加：

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

并给 `<activity>` 标签加上以下属性（防止旋转时 Activity 重建导致播放中断）：

```xml
android:configChanges="orientation|screenSize|keyboardHidden|screenLayout|smallestScreenSize"
android:screenOrientation="fullSensor"
```

然后运行：

```bash
flutter run          # 连接手机/模拟器直接调试
flutter build apk    # 打包正式 APK（产物在 build/app/outputs/flutter-apk/）
```

## 项目结构

```
pan_video_player/
├── pubspec.yaml                  # 依赖：media_kit / dio / sqflite / inappwebview
├── lib/
│   ├── main.dart                 # 入口：初始化 media_kit
│   ├── app.dart                  # 根组件：主题、登录态、底部导航
│   ├── config/app_config.dart    # ★ 百度密钥配置 + 倍速档位（唯一要改的文件）
│   ├── models/models.dart        # 数据模型：账号 / 网盘文件 / 播放进度
│   ├── services/                 # ── 业务逻辑与网络层 ──
│   │   ├── auth_service.dart     #   多账号增删切换 + 本地持久化
│   │   ├── baidu_pan_api.dart    #   百度官方API：OAuth/文件列表/搜索/下载直链
│   │   └── progress_service.dart #   SQLite 存播放进度（断点续播）
│   └── pages/                    # ── 页面层 ──
│       ├── login_page.dart       #   授权登录（内嵌WebView抓取token）
│       ├── home_page.dart        #   文件浏览：目录导航/搜索/视频筛选
│       ├── player_page.dart      #   播放页：原画播放/缩放/倍速/续播（核心）
│       └── mine_page.dart        #   账号管理 + 设置
└── docs/打包指南.md               # 环境/打包/签名/常见报错
```

## 功能对照表

| 需求 | 实现 |
|---|---|
| 百度网盘授权登录 | 官方 OAuth implicit 授权，内嵌 WebView 抓取 access_token |
| 多账号管理切换 | auth_service 本地存多账号，首页/我的页一键切换 |
| 文件浏览导航搜索 | xpan/file `method=list` + `method=search`，视频文件高亮可点，非视频置灰 |
| 原画质播放 | `method=file_download` 拿原始文件 dlink，mpv 带 UA 流式播放，不经转码 |
| 手势缩放 | InteractiveViewer，双指 1x~5x 缩放，放大后拖动，一键复位 |
| 倍速 0.5x~3.0x | player.setRate 八档选择面板 |
| 进度记忆/断点续播 | SQLite 每 5 秒存进度，重新打开自动续播并提示 |
| 横竖屏适配 | 播放页自由旋转 + 手动切换按钮，configChanges 防重建 |

## 重要说明

- **画质无损的原理**：播放的是网盘里"原始文件"的下载直链（官方接口），不是官方 App 的转码流，分辨率与码率取决于原文件本身。
- **下载速度**：受百度账号等级限制（非会员账号下载直链限速，这是百度侧规则，任何第三方工具都无法绕过）。播放卡顿时属正常现象，建议缓冲或升级账号。
- **合规性**：仅使用百度网盘官方开放平台公开接口，不破解、不改协议；登录操作由用户本人完成并授权。
