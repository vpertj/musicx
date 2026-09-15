/// 下载源(含国内加速代理)的选择与回退(纯函数,便于单测)。
///
/// 背景:GitHub 的 release 资产**不在 github.com 上**,而是 302 到
/// `release-assets.githubusercontent.com`(实际落在 Azure Blob)。
/// 国内访问该域名经常只有几十 KB/s 甚至断流;`api.github.com` 更是
/// 常见的 DNS 污染/超时目标。
///
/// 策略:**直连优先**(境外用户与 GitHub 自身最稳),失败后依次尝试
/// 免费公共加速代理。任何来源下载到的文件都必须通过 SHA256 校验,
/// 因此引入第三方代理不会降低安全性 —— 被篡改的包会在校验处被拒。
library;

/// 一个下载源的定义。
class DownloadSource {
  /// 展示用名称(错误信息里告诉用户走了哪条路)。
  final String label;

  /// 把原始 GitHub URL 转成本源可用的 URL。
  ///
  /// 直连源返回原 URL;代理源在前面拼上代理前缀。
  final String Function(String originalUrl) rewrite;

  /// 是否为第三方代理(用于提示与统计)。
  final bool isProxy;

  const DownloadSource({
    required this.label,
    required this.rewrite,
    this.isProxy = false,
  });

  /// 直连 GitHub(不经过任何第三方)。
  static const DownloadSource direct = DownloadSource(
    label: 'GitHub 直连',
    rewrite: _identity,
  );

  static String _identity(String url) => url;

  /// 用代理前缀构造一个下载源。
  factory DownloadSource.proxy(String prefix, {String? label}) {
    // 去掉末尾斜杠,避免拼出 `//https://...`
    final base = prefix.endsWith('/')
        ? prefix.substring(0, prefix.length - 1)
        : prefix;
    return DownloadSource(
      label: label ?? Uri.tryParse(base)?.host ?? base,
      rewrite: (url) => '$base/$url',
      isProxy: true,
    );
  }
}

/// 实测可用的免费公共加速代理(2026-09 实测)。
///
/// **分两类**,因为实测发现它们能力不同,不能混用:
///
/// [kApiCapableProxyPrefixes] 既能透传 `api.github.com`(可取到 SHA256
/// digest),也能代理 release 资产下载。用于「检查更新」的降级路径。
///
/// [kDownloadOnlyProxyPrefixes] **只代理下载**;对 api.github.com 返回
/// 403("Invalid input.")。用于「下载」环节 —— 检查更新时不能用它们,
/// 否则会因为拿不到 digest 而丧失完整性校验能力。
///
/// 验证方式:完整下载 62.9MB APK 并比对 SHA256,与 GitHub 官方逐字节一致。
///
/// 注意:公共代理的稳定性**不可控**,随时可能限速或关停。因此:
///   1. 它们只作为直连失败后的回退,不作为主路径;
///   2. 逐个尝试而非只用一个;
///   3. 下载后必须通过 SHA256 校验。
const kApiCapableProxyPrefixes = <String>[
  'https://gh-proxy.com',
  'https://gh.llkk.cc',
];

/// 只代理下载、不支持 api.github.com 的代理(实测 API 返回 403)。
const kDownloadOnlyProxyPrefixes = <String>[
  'https://ghfast.top',
  'https://ghproxy.net',
];

/// 全部下载可用代理(API 能力优先,便于统一轮询)。
const kPublicProxyPrefixes = <String>[
  ...kApiCapableProxyPrefixes,
  ...kDownloadOnlyProxyPrefixes,
];

/// 把 URL 包一层代理前缀(供"检查更新"等单点请求复用)。
String proxyWrap(String prefix, String url) {
  final base = prefix.endsWith('/')
      ? prefix.substring(0, prefix.length - 1)
      : prefix;
  return '$base/$url';
}

/// 只对 GitHub 域名做代理改写。
///
/// 已经是指向代理自身的 URL、或非 GitHub 的 URL(例如用户自建 OSS)
/// 不应再叠加代理 —— 否则会拼出 `proxy/https://proxy/https://...`。
bool isRewritableGitHubUrl(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  return host == 'github.com' ||
      host.endsWith('.github.com') ||
      host == 'githubusercontent.com' ||
      host.endsWith('.githubusercontent.com');
}

/// 构造下载源列表(直连在前,代理按给定顺序在后)。
///
/// [proxies] 为空时返回只含直连的列表(便于测试与"禁用代理"场景)。
List<DownloadSource> buildDownloadSources({List<String> proxies = kPublicProxyPrefixes}) {
  return <DownloadSource>[
    DownloadSource.direct,
    for (final p in proxies) DownloadSource.proxy(p),
  ];
}

/// 按顺序尝试各下载源时,判断某个错误是否值得换源重试。
///
/// 超时、连接失败、5xx、403(限流)都值得换源;
/// 而 404(资产真的不存在)换源也没用,应当直接失败以免白等三轮。
bool shouldTryNextSource({
  required int? statusCode,
  required bool timedOut,
  required bool connectionFailed,
}) {
  if (timedOut) return true;
  if (connectionFailed) return true;
  if (statusCode == null) return true;
  if (statusCode >= 500) return true;
  // 403/429:GitHub 或代理的限流,换个源可能就好了
  if (statusCode == 403 || statusCode == 429) return true;
  // 404/410:资产不存在,换源无意义
  return false;
}
