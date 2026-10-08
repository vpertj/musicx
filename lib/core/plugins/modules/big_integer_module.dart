/// require("big-integer") 的替代实现,供插件运行时白名单使用。
///
/// 生态音源(网易云 / 网易云电台)仅用到 `bigInt(str, radix)` 构造、
/// `.modPow(e, m)` 与 `.toString(radix)`,用于登录/RSA 参数加密。
/// 本 shim 基于引擎原生 BigInt(macOS JavaScriptCore 与 Android V8 均支持,
/// 已在测试中验证),实现 big-integer 常用链式 API 子集,零外部依赖。
const String bigIntegerModuleSource = r'''
(function (globalThis_) {
  function toBigInt(value, radix) {
    if (value instanceof BI) return value.value;
    if (typeof value === "bigint") return value;
    if (typeof value === "number") {
      if (!Number.isInteger(value)) {
        throw new Error("big-integer shim: 仅支持整数, got " + value);
      }
      return BigInt(value);
    }
    var s = String(value).trim();
    var neg = false;
    if (s.charAt(0) === "-") { neg = true; s = s.slice(1); }
    var base = radix === undefined ? 10 : Number(radix);
    if (base === 10 && /^0[xX]/.test(s)) { base = 16; s = s.slice(2); }
    var digits = "0123456789abcdefghijklmnopqrstuvwxyz";
    var acc = 0n;
    var b = BigInt(base);
    var lower = s.toLowerCase();
    for (var i = 0; i < lower.length; i++) {
      var d = digits.indexOf(lower.charAt(i));
      if (d < 0 || d >= base) {
        throw new Error("big-integer shim: invalid digit '" + lower.charAt(i) + "' for radix " + base);
      }
      acc = acc * b + BigInt(d);
    }
    return neg ? -acc : acc;
  }

  function BI(value) {
    if (!(this instanceof BI)) return new BI(value);
    if (value instanceof BI) { this.value = value.value; return; }
    if (typeof value === "bigint") { this.value = value; return; }
    // 兼容 bigInt(number|string, radix) 调用形式
    this.value = value;
  }

  function wrap(v) { return new BI(v); }

  BI.prototype._b = function (other, radix) { return toBigInt(other, radix); };

  BI.prototype.add = function (o, r) { return wrap(this.value + this._b(o, r)); };
  BI.prototype.subtract = function (o, r) { return wrap(this.value - this._b(o, r)); };
  BI.prototype.multiply = function (o, r) { return wrap(this.value * this._b(o, r)); };
  BI.prototype.divide = function (o, r) {
    if (this._b(o, r) === 0n) throw new Error("big-integer shim: divide by zero");
    return wrap(this.value / this._b(o, r));
  };
  BI.prototype.mod = function (o, r) {
    var m = this._b(o, r);
    if (m === 0n) throw new Error("big-integer shim: mod by zero");
    var res = this.value % m;
    if (res < 0n && m > 0n) res += m;
    return wrap(res);
  };
  BI.prototype.pow = function (o, r) { return wrap(this.value ** this._b(o, r)); };
  BI.prototype.abs = function () { return wrap(this.value < 0n ? -this.value : this.value); };
  BI.prototype.negate = function () { return wrap(-this.value); };

  BI.prototype.modPow = function (exp, mod) {
    var e = this._b(exp), m = this._b(mod);
    if (m === 0n) throw new Error("big-integer shim: modPow by zero");
    var negativeExp = false;
    if (e < 0n) { negativeExp = true; e = -e; }
    var base = ((this.value % m) + m) % m;
    var result = 1n % ((m < 0n ? -m : m));
    var mm = m < 0n ? -m : m;
    while (e > 0n) {
      if (e & 1n) result = (result * base) % mm;
      base = (base * base) % mm;
      e >>= 1n;
    }
    if (negativeExp) {
      // 负指数求模逆(big-integer 支持;音源场景不使用,给出明确错误)
      throw new Error("big-integer shim: modPow with negative exponent unsupported");
    }
    return wrap(result);
  };

  BI.prototype.compare = function (o, r) {
    var b = this._b(o, r);
    return this.value === b ? 0 : this.value > b ? 1 : -1;
  };
  BI.prototype.equals = function (o, r) { return this.compare(o, r) === 0; };
  BI.prototype.greater = function (o, r) { return this.compare(o, r) > 0; };
  BI.prototype.greaterOrEquals = function (o, r) { return this.compare(o, r) >= 0; };
  BI.prototype.lesser = function (o, r) { return this.compare(o, r) < 0; };
  BI.prototype.lesserOrEquals = function (o, r) { return this.compare(o, r) <= 0; };

  Object.defineProperty(BI.prototype, "isZero", {
    get: function () { return this.value === 0n; },
  });
  Object.defineProperty(BI.prototype, "isPositive", {
    get: function () { return this.value > 0n; },
  });
  Object.defineProperty(BI.prototype, "isNegative", {
    get: function () { return this.value < 0n; },
  });
  Object.defineProperty(BI.prototype, "isEven", {
    get: function () { return (this.value & 1n) === 0n; },
  });
  Object.defineProperty(BI.prototype, "isOdd", {
    get: function () { return (this.value & 1n) === 1n; },
  });

  BI.prototype.toJSNumber = function () { return Number(this.value); };
  BI.prototype.valueOf = function () { return this.value; };
  BI.prototype.toString = function (radix) {
    var base = radix === undefined ? 10 : Number(radix);
    if (base === 10) return this.value.toString();
    var digits = "0123456789abcdefghijklmnopqrstuvwxyz";
    var neg = this.value < 0n;
    var v = neg ? -this.value : this.value;
    var b = BigInt(base);
    if (v === 0n) return "0";
    var s = "";
    while (v > 0n) {
      s = digits[Number(v % b)] + s;
      v = v / b;
    }
    return (neg ? "-" : "") + s;
  };

  function bigInt(value, radix) {
    return new BI(toBigInt(value, radix));
  }
  // UMD 宿主里 bigInt 常带静态成员,保守补齐常用的几个
  bigInt.ZERO = bigInt(0);
  bigInt.ONE = bigInt(1);

  module.exports = bigInt;
})(this);
''';
