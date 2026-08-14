import 'dart:async';
import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;

/// 安全版 XHR 桥(替代 flutter_js 自带 enableXhr)。
///
/// flutter_js 0.8.7 的 enableXhr 把响应文本直接嵌入 JS 模板字面量:
///   evaluate("...callback($info, `$responseText`, $error)")
/// 响应 JSON 字符串值里的 `\n` 会被模板字面量解释成真实换行,导致
/// 含多行文本(如网易云歌词接口返回的 lrc.lyric)的响应无法被 JSON.parse。
/// 这里改用 jsonEncode 生成 JS 字符串字面量,可无损承载任意响应文本。
///
/// 其余行为与 flutter_js 一致:XMLHttpRequest 走 http 包异步发送,
/// pending 调用由 40ms 定时器排空,回调经 onMessage('SendNative') 进入 Dart。
const String _xhrJsCode = '''
function XMLHttpRequest() {
  this._send_native = XMLHttpRequestExtension_send_native;
  this._httpMethod = null;
  this._url = null;
  this._requestHeaders = [];
  this._responseHeaders = [];
  this.response = null;
  this.responseText = null;
  this.responseXML = null;
  this.responseType = "";
  this.onreadystatechange = null;
  this.onloadstart = null;
  this.onprogress = null;
  this.onabort = null;
  this.onerror = null;
  this.onload = null;
  this.onloadend = null;
  this.ontimeout = null;
  this.readyState = 0;
  this.status = 0;
  this.statusText = "";
  this.withCredentials = null;
};
XMLHttpRequest.UNSENT = 0;
XMLHttpRequest.OPENED = 1;
XMLHttpRequest.HEADERS = 2;
XMLHttpRequest.LOADING = 3;
XMLHttpRequest.DONE = 4;
XMLHttpRequest.prototype.constructor = XMLHttpRequest;
XMLHttpRequest.prototype.open = function(httpMethod, url) {
  this._httpMethod = httpMethod;
  this._url = url;
  this.readyState = XMLHttpRequest.OPENED;
  if (typeof this.onreadystatechange === "function") {
    this.onreadystatechange();
  }
};
XMLHttpRequest.prototype.send = function(data) {
  this.readyState = XMLHttpRequest.LOADING;
  if (typeof this.onreadystatechange === "function") {
    this.onreadystatechange();
  }
  if (typeof this.onloadstart === "function") {
    this.onloadstart();
  }
  var that = this;
  this._send_native(this._httpMethod, this._url, this._requestHeaders, data || null, function(responseInfo, responseText, error) {
    that._send_native_callback(responseInfo, responseText, error);
  }, this);
};
XMLHttpRequest.prototype.abort = function() {
  this.readyState = XMLHttpRequest.UNSENT;
};
XMLHttpRequest.prototype._send_native_callback = function(responseInfo, responseText, error) {
  if (this.readyState === XMLHttpRequest.UNSENT) {
    if (typeof this.onabort === "function") {
      this.onabort();
    }
    return;
  }
  if (this.readyState != XMLHttpRequest.LOADING) {
    return;
  }
  this.responseURL = this._url;
  this.status = responseInfo.statusCode;
  this.statusText = responseInfo.statusText;
  this._responseHeaders = responseInfo.responseHeaders || [];
  this.readyState = XMLHttpRequest.DONE;
  this.response = null;
  this.responseText = null;
  this.responseXML = null;
  if (error) {
    this.responseText = error;
  } else {
    this.responseText = responseText;
    switch (this.responseType) {
      case "":
      case "text":
        this.response = this.responseText;
        break;
      case "document":
        this.response = this.responseText;
        this.responseXML = this.responseText;
        break;
      case "json":
        try {
            this.response = JSON.parse(responseText);
        }
        catch (e) {
            error = "Could not parse JSON response: " + responseText;
        }
        break;
      default:
        error = "Unsupported responseType: " + responseInfo.responseType;
    }
  }
  this.readyState = XMLHttpRequest.DONE;
  if (typeof this.onreadystatechange === "function") {
    this.onreadystatechange();
  }
  if (error === "timeout") {
    if (typeof this.ontimeout === "function") {
      this.ontimeout();
    }
  } else if (error) {
    if (typeof this.onerror === "function") {
      this.onerror();
    }
  } else {
    if (typeof this.onload === "function") {
      this.onload();
    }
  }
  if (typeof this.onloadend === "function") {
    this.onloadend();
  }
};
XMLHttpRequest.prototype.setRequestHeader = function(header, value) {
  this._requestHeaders.push([header, value]);
};
XMLHttpRequest.prototype.getAllResponseHeaders = function() {
  var ret = "";
  for (var i = 0; i < this._responseHeaders.length; i++) {
    var keyValue = this._responseHeaders[i];
    ret += keyValue[0] + ": " + keyValue[1] + "\\r\\n";
  }
  return ret;
};
XMLHttpRequest.prototype.getResponseHeader = function(name) {
  var ret = "";
  for (var i = 0; i < this._responseHeaders.length; i++) {
    var keyValue = this._responseHeaders[i];
    if (keyValue[0] !== name) continue;
    if (ret === "") ret += ", ";
    ret += keyValue[1];
  }
  return ret;
};
this.XMLHttpRequest = XMLHttpRequest;
''';

const String _sendNativeJs = '''
var xhrRequests = {};
var idRequest = -1;
function XMLHttpRequestExtension_send_native() {
  idRequest += 1;
  var cb = arguments[4];
  xhrRequests[idRequest] = {
    callback: function(responseInfo, responseText, error) {
      cb(responseInfo, responseText, error);
    }
  };
  var args = [];
  args[0] = arguments[0];
  args[1] = arguments[1];
  args[2] = arguments[2];
  args[3] = arguments[3];
  args[4] = idRequest;
  sendMessage('SendNative', JSON.stringify(args));
}
''';

class _XhrPendingCall {
  final int idRequest;
  final String method;
  final String url;
  final Map<String, String> headers;
  final String? body;
  _XhrPendingCall({
    required this.idRequest,
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
  });
}

/// 为 [runtime] 安装安全 XHR 桥,返回时 XMLHttpRequest 已可用。
/// 替代 flutter_js 的 `runtime.enableXhr()`(见文件头注释)。
JavascriptRuntime enableSafeXhr(JavascriptRuntime runtime) {
  const pendingKey = 'musicx_xhr_pending';
  runtime.dartContext[pendingKey] = <_XhrPendingCall>[];
  http.Client? client = http.Client();

  final evalSend = runtime.evaluate(_sendNativeJs);
  if (evalSend.isError) {
    throw StateError(
      'failed to init xhr send bridge: ${evalSend.stringResult}',
    );
  }
  final evalXhr = runtime.evaluate(_xhrJsCode);
  if (evalXhr.isError) {
    throw StateError('failed to init XMLHttpRequest: ${evalXhr.stringResult}');
  }
  runtime.localContext['musicxXhr'] = evalXhr.rawResult;
  runtime.localContext['musicxXhrSend'] = evalSend.rawResult;

  // 定时排空 pending 请求;与 flutter_js 自带桥一致,随 runtime 生命周期常驻。
  Timer.periodic(const Duration(milliseconds: 40), (timer) {
    final pending = runtime.dartContext[pendingKey] as List<_XhrPendingCall>?;
    if (pending == null || pending.isEmpty) return;
    final calls = List<_XhrPendingCall>.from(pending);
    pending.clear();
    for (final call in calls) {
      _dispatch(runtime, call, client);
    }
  });

  runtime.onMessage('SendNative', (arguments) {
    try {
      final list =
          runtime.dartContext[pendingKey] as List<_XhrPendingCall>? ?? [];
      runtime.dartContext[pendingKey] = list;
      list.add(
        _XhrPendingCall(
          idRequest: (arguments[4] as num).toInt(),
          method: arguments[0] as String,
          url: arguments[1] as String,
          headers: {
            for (final h in (arguments[2] as List).cast<List>())
              h[0] as String: h[1] as String,
          },
          body: arguments[3] as String?,
        ),
      );
    } catch (_) {
      // 忽略异常参数
    }
  });

  return runtime;
}

Future<void> _dispatch(
  JavascriptRuntime runtime,
  _XhrPendingCall call,
  http.Client client,
) async {
  late http.Response response;
  final method = call.method.toUpperCase();
  final uri = Uri.parse(call.url);
  try {
    response = switch (method) {
      'GET' => await client.get(uri, headers: call.headers),
      'POST' => await client.post(uri, body: call.body, headers: call.headers),
      'PUT' => await client.put(uri, body: call.body, headers: call.headers),
      'PATCH' => await client.patch(
        uri,
        body: call.body,
        headers: call.headers,
      ),
      'DELETE' => await client.delete(uri, headers: call.headers),
      'HEAD' => await client.head(uri, headers: call.headers),
      _ => throw UnsupportedError('unsupported method: $method'),
    };
  } catch (e) {
    // 网络错误:把错误文本回传 JS 触发 onerror
    final errorText = jsonEncode(e.toString());
    runtime.evaluate(
      'globalThis.xhrRequests[${call.idRequest}].callback(${_infoJson(0, 'Network Error')}, $errorText, null);',
    );
    return;
  }
  final responseText = utf8.decode(response.bodyBytes);
  final info =
      '{"statusCode":${response.statusCode},"statusText":"OK","responseHeaders":[]}';
  runtime.evaluate(
    'globalThis.xhrRequests[${call.idRequest}].callback($info, ${jsonEncode(responseText)}, null);',
  );
}

String _infoJson(int code, String text) =>
    '{"statusCode":$code,"statusText":${jsonEncode(text)},"responseHeaders":[]}';
