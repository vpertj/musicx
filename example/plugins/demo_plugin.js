// 模拟 MusicFree 协议的本地示例插件(文档用途;端到端测试读取本文件验证全链路)。
// 协议要点:
// - module.exports 导出 { platform, version, srcUrl, search, getMediaSource }
// - search 返回 Promise(异步搜索),getMediaSource 同步返回播放地址
// v0.2.0:search 返回多首 SoundHelix 公开测试音频;getMediaSource 按 songId 映射真实可播 URL。
module.exports = {
  platform: "demo",
  version: "0.2.0",
  srcUrl: "",
  search: function (query) {
    return new Promise(function (resolve) {
      setTimeout(function () {
        resolve({
          isEnd: true,
          data: [
            { id: "s1", title: "SoundHelix 示例曲 1", artist: "SoundHelix", album: "Sample",
              artwork: "", duration: 369000, platform: "demo", songId: "s1", extra: {} },
            { id: "s2", title: "SoundHelix 示例曲 2", artist: "SoundHelix", album: "Sample",
              artwork: "", duration: 391000, platform: "demo", songId: "s2", extra: {} }
          ]
        });
      }, 20);
    });
  },
  getMediaSource: function (musicItem) {
    var idx = musicItem.songId.replace("s", "");
    return { url: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-" + idx + ".mp3" };
  }
};
