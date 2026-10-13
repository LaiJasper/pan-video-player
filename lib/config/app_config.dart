// ============================================================
// lib/config/app_config.dart — 全局配置（★唯一需要你手工修改的文件★）
//
// AppKey 获取步骤（重要！）：
// 1. 打开百度网盘开放平台 https://pan.baidu.com/union
// 2. 注册成为个人开发者（免费），实名认证
// 3. 「控制台 → 创建应用」→ 应用类型选"移动应用"
// 4. 拿到 AppKey 后，两种填法任选其一：
//    a) 云端打包（推荐）：不用改代码，把 AppKey 配到打包平台的
//       环境变量 BAIDU_APP_KEY 里即可（见 docs/打包指南.md 方案B）
//    b) 本地打包：直接把下面的 defaultValue 换成你的 AppKey
// ============================================================
class AppConfig {
  /// 百度网盘开放平台 AppKey（已由用户提供，2026-10-13）
  /// 编译时也可通过 --dart-define=BAIDU_APP_KEY=xxx 覆盖（云端打包用 Secrets 注入）
  static const String baiduAppKey =
      String.fromEnvironment('BAIDU_APP_KEY',
          defaultValue: 'U5fUqTR1jnHSgF38U8I8vGwWhurdkjvF');

  /// 百度网盘开放平台 SecretKey
  /// 说明：采用"implicit 授权"（token 直接返回，不走服务器换取），
  /// 移动端单机应用用不到 SecretKey；也请勿把 SecretKey 发给任何人。
  static const String baiduSecretKey =
      String.fromEnvironment('BAIDU_SECRET_KEY', defaultValue: '');

  /// OAuth 授权回调地址。
  /// 'oob' 是百度为移动端/桌面端提供的内置回调模式：
  /// 授权成功后页面 URL 中会携带 access_token，App 内嵌 WebView 读取即可。
  /// 若你在开放平台创建了应用并配置了专属回调地址，请改成一致的值。
  static const String redirectUri = 'oob';

  /// 申请的权限范围：basic=基本信息，netdisk=网盘文件读写
  static const String scope = 'basic,netdisk';

  /// 倍速档位（0.5x ~ 3.0x 共 8 档）
  static const List<double> speedOptions = [
    0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0,
  ];

  /// 倍速默认档位下标（对应上面列表，默认 1.0x = 下标2）
  static const int defaultSpeedIndex = 2;

  /// 视频文件扩展名（百度网盘 category==1 已标视频，
  /// 这里作为兜底判断，防止个别格式归类不准）
  static const List<String> videoExtensions = [
    '.mp4', '.mkv', '.avi', '.mov', '.flv', '.wmv',
    '.webm', '.m4v', '.ts', '.rmvb', '.rm', '.3gp', '.mpg', '.mpeg',
  ];
}
