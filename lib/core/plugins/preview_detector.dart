/// 试听片段判定(纯函数,便于单测)。
///
/// 背景:腾讯音乐 / 网易云等音源在未登录(或非会员)时,对 VIP 歌曲返回
/// 20 秒试听音频,而搜索结果里的 `duration` 仍是整曲时长,所以「看元数据
/// 正常、一听只有 20 秒」。
///
/// 判定依据:
/// - 已知歌曲时长时,按 128kbps 估算整曲应有体积,明显偏小即视为片段;
///   这样能覆盖 20 秒试听(~320KB),而单纯用「小于 256KB」会漏掉。
/// - 时长未知时回落到体积阈值。
library;

/// 128kbps ≈ 16KB/s。
const int _bytesPerSecond = 16000;

/// 时长未知时使用的体积阈值。
///
/// 实测(安卓真机):酷我等源搜索结果不带时长,此时仅靠体积判断:
/// - 0.18MB = 「请在手机客户端播放」提示音
/// - 1.26MB = 128kbps 约 80 秒片段
/// 而正常整曲(3 分钟以上 128kbps)普遍 >2MB,故阈值取 1.5MB 以内才能挡住
/// 1.26MB 这类片段。代价:极短的完整曲(60~90 秒)在时长未知时也可能被判为
/// 片段,此时会继续换源,实在只有它才明确报错(产品决策:不播片段)。
const int _unknownDurationThreshold = 1536 * 1024;

/// 估算与实际体积之比低于该比例即认为是片段。
const double _previewRatio = 0.5;

/// [contentLength] 为已知音频字节数(<=0 表示未知)。
/// [durationMs] 为歌曲时长(毫秒,<=0 或 null 表示未知)。
bool looksLikePreview({required int contentLength, int? durationMs}) {
  if (contentLength <= 0) return false;
  final expected = (durationMs != null && durationMs > 0)
      ? durationMs / 1000 * _bytesPerSecond
      : null;
  if (expected == null) return contentLength < _unknownDurationThreshold;
  return contentLength < expected * _previewRatio;
}
