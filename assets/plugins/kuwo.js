// 酷我音乐音源插件(MusicFree 协议,自包含,无 require 依赖)。
// - 搜索:酷我 web 搜索接口(无需登录)
// - 播放:anti.s 接口返回 https 直接 mp3 地址(完整歌曲)
// 注意:部分歌曲为试听/片段,getMediaSource 返回空则无法播放。
module.exports = {
  platform: "kuwo",
  version: "0.1.0",
  srcUrl: "",
  search: function (keyword, page, type) {
    var kw = (keyword || "").trim();
    if (!kw) return Promise.resolve({ isEnd: true, data: [] });
    var pn = ((page || 1) - 1) * 1;
    var url = "http://search.kuwo.cn/r.s?all=" + encodeURIComponent(kw) +
      "&ft=music&itemset=web_2013&client=kt&pn=" + pn +
      "&rn=30&rformat=json&encoding=utf8&pcjson=1";
    return fetch(url, {
      headers: {
        "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        referer: "http://www.kuwo.cn/"
      }
    })
      .then(function (resp) { return resp.json(); })
      .then(function (json) {
        var abs = (json && json.abslist) || [];
        var data = abs.map(function (s) {
          var rid = (s.MUSICRID || "").replace("MUSIC_", "");
          var pic = s.web_albumpic_short || s.albumpic_short || "";
          return {
            id: rid || s.DC_TARGETID || "",
            title: s.NAME || s.SONGNAME || "",
            artist: s.ARTIST || s.AARTIST || "",
            album: s.ALBUM || "",
            artwork: pic ? "https://" + pic : "",
            duration: (s.DURATION || 0) * 1000,
            platform: "kuwo",
            songId: rid,
            extra: {}
          };
        });
        // 智能过滤翻唱:若搜索词命中歌手名,只保留该歌手原唱
        var kw = (keyword || "").trim().toLowerCase();
        var hasSingerHit = data.some(function (it) {
          var a = (it.artist || "").toLowerCase();
          return a === kw || a.indexOf(kw + " / ") === 0 ||
            a.indexOf(" / " + kw) >= 0 || a.split("/").indexOf(kw) >= 0;
        });
        if (hasSingerHit) {
          data = data.filter(function (it) {
            var a = (it.artist || "").toLowerCase();
            return a === kw || a.split("/").some(function (x) {
              return x.trim() === kw;
            });
          });
        }
        return { isEnd: true, data: data };
      });
  },
  getMediaSource: function (musicItem) {
    var rid = "MUSIC_" + (musicItem && (musicItem.songId || musicItem.id)) || "";
    return new Promise(function (resolve) {
      fetch("https://antiserver.kuwo.cn/anti.s?type=convert_url3&rid=" + rid + "&format=mp3", {
        headers: {
          "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
          referer: "http://www.kuwo.cn/"
        }
      })
        .then(function (resp) { return resp.json(); })
        .then(function (d) {
          resolve({ url: (d && d.url) || "" });
        })
        .catch(function () { resolve({ url: "" }); });
    });
  }
};
