import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_js/flutter_js.dart';
import 'package:musicx/core/plugins/modules/axios_module.dart';
import 'package:musicx/core/plugins/modules/cheerio_module.dart';
import 'package:musicx/core/plugins/modules/crypto_js_module.dart';
import 'package:musicx/core/plugins/modules/dayjs_module.dart';
import 'package:musicx/core/plugins/modules/he_module.dart';
import 'package:musicx/core/plugins/modules/qs_module.dart';
import 'package:musicx/core/plugins/modules/big_integer_module.dart';
import 'package:musicx/core/plugins/xhr_safe.dart';
import 'dart:convert';

/// require() 白名单注册表:插件可 require 的模块(与 MusicFree 宿主对齐)。
const String moduleRegistrySource = r'''
var __musicx_modules = {};
function __musicx_require(name) {
  if (Object.prototype.hasOwnProperty.call(__musicx_modules, name)) {
    return __musicx_modules[name];
  }
  throw new Error("require() not supported: " + name);
}
function __musicx_define(name, factory) {
  var m = { exports: {} };
  try {
    factory(m, m.exports, __musicx_require);
  } catch (e) {
    throw new Error("module[" + name + "] init failed: " + (e && e.message || e));
  }
  __musicx_modules[name] = m.exports;
}
''';

/// 基于 XMLHttpRequest shim 的 fetch polyfill(内联字符串版)。
///
/// flutter_js 自带的 enableFetch() 通过 rootBundle 异步加载 fetch.js,
/// 而插件运行在独立 isolate,rootBundle(ServicesBinding) 不可用,会抛
/// "Binding has not yet been initialized"。因此这里把等价的 polyfill
/// 内联为常量,配合同步的 enableXhr() 在任意 isolate 中直接注入。
/// (参考 flutter_js 0.8.7 assets/js/fetch.js,Apache-2.0)
const String fetchPolyfillSource = r'''
function fetch(url, options) {
  options = options || {};
  return new Promise(function (resolve, reject) {
    var request = new XMLHttpRequest();
    var keys = [];
    var all = [];
    var headers = {};

    var response = function () {
      return {
        ok: (request.status / 100 | 0) == 2,
        statusText: request.statusText,
        status: request.status,
        url: request.responseURL,
        text: function () { return Promise.resolve(request.responseText); },
        json: function () {
          return new Promise(function (res, rej) {
            try {
              res(JSON.parse(request.responseText));
            } catch (e) {
              rej(e);
            }
          });
        },
        headers: {
          keys: function () { return keys; },
          entries: function () { return all; },
          get: function (n) { return headers[n.toLowerCase()]; },
          has: function (n) { return n.toLowerCase() in headers; }
        }
      };
    };

    request.open(options.method || 'get', url, true);
    request.onload = function () {
      request.getAllResponseHeaders().replace(/^(.*?):[^\S\n]*([\s\S]*?)$/gm,
        function (m, key, value) {
          keys.push(key = key.toLowerCase());
          all.push([key, value]);
          headers[key] = headers[key] ? headers[key] + ',' + value : value;
        });
      resolve(response());
    };
    request.onerror = function () { reject(new Error('network error: ' + url)); };
    request.withCredentials = options.credentials == 'include';

    if (options.headers) {
      for (var i in options.headers) {
        if (Object.prototype.hasOwnProperty.call(options.headers, i)) {
          request.setRequestHeader(i, options.headers[i]);
        }
      }
    }
    request.send(options.body || null);
  });
}
''';

/// 创建 JavascriptRuntime 的封装,便于测试替换。
class JsRuntimeFactory {
  static JavascriptRuntime create() => getJavascriptRuntime();

  /// 创建可在独立 isolate 中使用的 runtime。
  ///
  /// 插件在 PluginSandbox 的 Isolate.run 中执行,该环境无 ServicesBinding,
  /// 不能使用 flutter_js 的 enableFetch()(内部依赖 rootBundle)。这里改用
  /// 同步的 enableSafeXhr() + 内联 fetch polyfill,两处都不依赖主 isolate 资源。
  /// 同时注入 require 白名单模块(axios/dayjs/he/crypto-js/cheerio),
  /// 兼容 MusicFree 官方插件的运行时依赖。
  static JavascriptRuntime createIsolateSafe() {
    final runtime = getJavascriptRuntime(xhr: false);
    enableSafeXhr(runtime);
    runtime.evaluate(fetchPolyfillSource);
    runtime.evaluate(moduleRegistrySource);
    defineModule(runtime, 'axios', axiosModuleSource);
    defineModule(runtime, 'dayjs', dayjsModuleSource);
    defineModule(runtime, 'he', heModuleSource);
    defineModule(runtime, 'crypto-js', crypto_jsModuleSource);
    defineModule(runtime, 'cheerio', cheerioModuleSource);
    defineModule(runtime, 'qs', qsModuleSource);
    defineModule(runtime, 'big-integer', bigIntegerModuleSource);
    // MusicFree 宿主 env API(部分生态插件依赖,如读用户 cookie)
    runtime.evaluate(
      'globalThis.env = { getUserVariables: function () { return {}; } };',
    );
    return runtime;
  }

  /// 注册一个 require 白名单模块(供 [createIsolateSafe] 与单测使用)。
  ///
  /// **失败只跳过该模块,绝不能让整个引擎起不来**:实测事故 —— 1.7.56 新增的
  /// `qs` / `big-integer` 在安卓上初始化报错,而这里原先直接 throw,于是运行环境
  /// 创建失败,**所有音源**都报 `failed to init module ...`:搜索全失败、首页
  /// 「热门推荐 / 猜你喜欢」全空(用户反馈「首页热门歌曲、推荐歌曲都没有」)。
  /// 真的需要该模块的插件会自己报错,影响范围可控。
  @visibleForTesting
  static void defineModule(
    JavascriptRuntime runtime,
    String name,
    String source,
  ) {
    final js =
        '__musicx_define(${jsonEncode(name)}, function (module, exports, require) {\n$source\n});';
    try {
      final r = runtime.evaluate(js);
      if (r.isError) {
        debugPrint('MusicX: 运行时模块 $name 初始化失败(已跳过): ${r.stringResult}');
      }
    } catch (e) {
      debugPrint('MusicX: 运行时模块 $name 初始化异常(已跳过): $e');
    }
  }
}
