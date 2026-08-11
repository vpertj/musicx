// 模拟 MusicFree 协议的本地示例插件(文档用途;测试以内嵌源码为准)。
// 协议要点:
// - module.exports 导出 { platform, version, srcUrl, search, getMediaSource }
// - search 返回 Promise(异步搜索),getMediaSource 同步返回播放地址
module.exports = {
  platform: "demo-source",
  version: "0.1.0",
  srcUrl: "",
  search: function (query) {
    return new Promise(function (resolve) {
      setTimeout(function () {
        resolve({
          isEnd: true,
          data: [
            { id: "d1", title: "示例歌曲", artist: "演示歌手", album: "演示专辑",
              artwork: "", duration: 180000, platform: "demo-source", songId: "d1", extra: {} }
          ]
        });
      }, 20);
    });
  },
  getMediaSource: function (musicItem) {
    return { url: "https://example.com/audio/" + musicItem.songId + ".mp3" };
  }
};
