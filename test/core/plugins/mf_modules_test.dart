import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/plugin_loader.dart';

/// 验证新增的 qs / big-integer 模块与 exports.default 解包。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('qs stringify matches netease eparams shape', () {
    final runtime = JsRuntimeFactory.createIsolateSafe();
    final js = '''
(function(){
  var qs = __musicx_require("qs");
  var pae = { asr: "1", ts: "1234", __u: "123", p: "abcd", epid: "", c: true };
  var es = { hf: "url", pt: qs.stringify(pae) };
  return JSON.stringify({ flat: qs.stringify({ a: 1, b: "x y&z", "中文": "值" }), nested: qs.stringify({ top: es }) });
})()
''';
    final r = runtime.evaluate(js);
    expect(r.isError, isFalse, reason: r.stringResult);
    final map = r.stringResult;
    // 扁平编码:空格 %20、& 转 %26、中文百分号编码
    expect(map, contains('"flat":"a=1'));
    expect(map, contains('b=x%20y%26z'));
    expect(map, contains('%E4%B8%AD%E6%96%87=%E5%80%BC'));
    // 嵌套对象 qs 默认输出 top[hf]=url&top[pt]=...
    expect(map, contains('top%5Bhf%5D'));
  });

  test('big-integer modPow matches known RSA vector', () {
    final runtime = JsRuntimeFactory.createIsolateSafe();
    final js = '''
(function(){
  var bigInt = __musicx_require("big-integer");
  // 与 netease Rsa() 同形态:hex 文本 modPow(65537, modulus) -> hex
  var d = "010001";
  var e = "00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7";
  var hexText = Bufferless("abc".split("").map(function(c){return c.charCodeAt(0).toString(16);}).join(""));
  function Bufferless(x){ return x; }
  var res = bigInt(hexText, 16).modPow(bigInt(d, 16), bigInt(e, 16)).toString(16);
  var basic = bigInt("ff", 16).add(bigInt("1", 16)).toString(16);
  return JSON.stringify({ res: res, len: res.length, basic: basic, isZero: bigInt(0).isZero, cmp: bigInt(10).compare(5) });
})()
''';
    final r = runtime.evaluate(js);
    expect(r.isError, isFalse, reason: r.stringResult);
    final out = r.stringResult;
    // RSA-1024:模数 256 hex 位,结果应为 256 位(首位 0x91 非零)
    expect(out, contains('"len":256'));
    expect(out, contains('"basic":"100"'));
    expect(out, contains('"isZero":true'));
    expect(out, contains('"cmp":1'));
  });

  test('cjsShim unwraps parcel exports.default', () {
    final runtime = JsRuntimeFactory.createIsolateSafe();
    final loader = PluginLoader(runtime);
    // 模拟 parcel 打包后的 netease.js 形态
    const source = '''
var pluginInstance = {
  platform: "网易云音乐",
  version: "0.0.1",
  search: function () { return { data: [] }; }
};
Object.defineProperty(module.exports, '__esModule', { value: true });
module.exports.default = pluginInstance;
''';
    final meta = loader.loadPlugin(source);
    expect(meta['platform'], '网易云音乐');
    expect(meta['version'], '0.0.1');
    final funcs = (meta['functions'] as List).cast<String>();
    expect(funcs, contains('search'));
  });
}
