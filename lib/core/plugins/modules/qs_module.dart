/// require("qs") 的轻量替代实现,供插件运行时白名单使用。
///
/// 仅实现生态音源实际用到的子集:default.stringify(obj)(网易云 eparams 的
/// URL 表单编码)。编码规则与 qs 默认行为一致:
/// encodeURIComponent + 空格转 %20,嵌套对象用 key[sub]=v,数组展开为重复 key。
///
/// 与 MusicFree 宿主环境对齐(宿主直接打包 npm qs);本实现为纯 JS,无依赖。
const String qsModuleSource = r'''
function stringifyValue(prefix, value, out) {
  if (value === null || value === undefined) return;
  if (Array.isArray(value)) {
    for (var i = 0; i < value.length; i++) {
      stringifyValue(prefix, value[i], out);
    }
    return;
  }
  if (typeof value === "object") {
    var keys = Object.keys(value);
    for (var k = 0; k < keys.length; k++) {
      stringifyValue(prefix + "[" + keys[k] + "]", value[keys[k]], out);
    }
    return;
  }
  out.push(
    encodeURIComponent(prefix) + "=" + encodeURIComponent(String(value))
  );
}

function qs_stringify(obj, options) {
  if (obj === null || obj === undefined || typeof obj !== "object") return "";
  // qs 默认(encodeValuesOnly=false 场景下音源传的都是普通对象):
  // 键与值都过 encodeURIComponent,空格为 %20。
  var parts = [];
  var keys = Object.keys(obj);
  for (var i = 0; i < keys.length; i++) {
    var key = keys[i];
    var val = obj[key];
    if (typeof val === "object" && val !== null) {
      stringifyValue(key, val, parts);
    } else if (val !== null && val !== undefined) {
      parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(val)));
    }
  }
  return parts.join("&");
}

function qs_parse(str) {
  var out = {};
  if (!str) return out;
  String(str)
    .replace(/^\?/, "")
    .split("&")
    .forEach(function (pair) {
      if (!pair) return;
      var idx = pair.indexOf("=");
      var k = idx < 0 ? pair : pair.slice(0, idx);
      var v = idx < 0 ? "" : pair.slice(idx + 1);
      try {
        out[decodeURIComponent(k.replace(/\+/g, " "))] = decodeURIComponent(
          v.replace(/\+/g, " ")
        );
      } catch (e) {
        out[k] = v;
      }
    });
  return out;
}

module.exports = { stringify: qs_stringify, parse: qs_parse };
module.exports["default"] = module.exports;
''';
