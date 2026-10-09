// test/core/plugins/js_runtime_factory_test.dart
//
// 用户反馈:「首页的热门歌曲、推荐歌曲等这些都没有」。
//
// 真机/模拟器取证:所有音源都报 `failed to init module ...` —— 运行环境创建时就
// 挂了。根因是 js_runtime_factory 里注册可选模块(qs / big-integer,1.7.56 新增)
// 时**直接 throw**:一个模块在安卓上初始化失败,整个引擎就起不来,于是搜索、
// 榜单、首页推荐全空。
//
// 本文件锁定:单个模块初始化失败只跳过它,引擎仍可用。
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/core/plugins/js_runtime_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('某个运行时模块初始化失败,不能拖垮整个引擎', () {
    // 用真实的隔离环境 runtime(带 require 注册表),与插件执行时同一套
    final runtime = JsRuntimeFactory.createIsolateSafe();
    // 故意塞一个编译不过的模块(等价于安卓上 qs/big-integer 初始化报错)
    expect(
      () => JsRuntimeFactory.defineModule(runtime, 'broken', 'var = ;'),
      returnsNormally,
      reason: '模块注册必须 best-effort:失败只跳过,不能 throw',
    );
    // 引擎仍可用
    final r = runtime.evaluate('1 + 1');
    expect(r.isError, isFalse);
    expect(r.stringResult, '2');
  });

  test('正常模块照常注册,require 拿得到', () {
    final runtime = JsRuntimeFactory.createIsolateSafe();
    JsRuntimeFactory.defineModule(
      runtime,
      'demo-mod',
      'module.exports = { hi: function () { return "ok"; } };',
    );
    final r = runtime.evaluate(
      'globalThis.__musicx_require("demo-mod").hi()',
    );
    expect(r.isError, isFalse);
    expect(r.stringResult, 'ok');
  });
}
