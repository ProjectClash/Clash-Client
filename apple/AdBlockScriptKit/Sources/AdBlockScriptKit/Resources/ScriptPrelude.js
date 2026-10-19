/*
 * Clash script prelude.
 *
 * Every platform API a rewrite script uses is implemented here, in JavaScript,
 * on top of a handful of native primitives. The reason is the platforms' own
 * history: the same script is expected to work on six hosts, and each host
 * spells the same three ideas (HTTP, storage, finishing) differently.
 * Implementing the compatibility layer in JavaScript means it can be read and
 * fixed by anyone who knows the scripts, and the native surface stays small
 * enough to audit.
 *
 * Native primitives, installed by the host before this file runs:
 *   __clashNative(operation, ...arguments)
 *
 * where the operation is one of `call` (a synchronous answer), `host` (an
 * answer later, through `__clashResolve`), `log`, `timer`, `cancel`, `now`.
 *
 * Two things here are load-bearing and easy to get wrong:
 *
 * 1. The platform globals are injected one platform at a time, never all at
 *    once. Env.js decides what host it is on by testing `$task`, then `$loon`,
 *    then `$rocket`, then `$environment["surge-version"]`, then
 *    `stash-version` — and `module.exports` before `$task`. A host that defines
 *    all of them is read as Quantumult X (or Node.js) by every script.
 * 2. Nothing named `module` or `exports` is defined. A truthy
 *    `module.exports` makes Env.js answer "Node.js", after which OpenAPI.js
 *    takes a `require` path that does not exist here.
 */
(function (global) {
  'use strict';

  // The host installs one function; each primitive is that function with its
  // operation bound, so the prelude reads by name and the native surface stays
  // a single auditable entry point.
  var nativeCall = global.__clashNative;
  delete global.__clashNative;
  function primitive(op) {
    return function () { return nativeCall.apply(null, [op].concat(Array.prototype.slice.call(arguments))); };
  }
  var callNative = primitive('call');
  var hostNative = primitive('host');
  var logNative = primitive('log');
  var timerNative = primitive('timer');
  var cancelNative = primitive('cancel');
  var nowNative = primitive('now');

  var state = {
    platform: 'loon',
    phase: 'request',
    // The URL of the request being processed. Quantumult X's own scripts
    // rewrite `$done({path: ...})` and expect the host to rebuild the URL.
    requestURL: '',
    argument: {},
    binaryBody: false,
    callbacks: {},
    nextCallback: 1,
    timers: {},
    nextTimer: 1,
    done: false,
    started: Date.now()
  };

  // ---------------------------------------------------------------------------
  // Bytes
  //
  // `binary-body-mode` hands scripts a Uint8Array; every platform has a slightly
  // different idea of how the same bytes get into and out of that array, and
  // strings are UTF-8 everywhere except where they are not. These helpers are
  // the only conversion points.

  function toBytes(value) {
    if (value === null || value === undefined) { return null; }
    if (value instanceof Uint8Array) { return value; }
    if (typeof ArrayBuffer !== 'undefined') {
      if (value instanceof ArrayBuffer) { return new Uint8Array(value); }
      if (ArrayBuffer.isView(value)) {
        return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
      }
    }
    if (Array.isArray(value)) { return new Uint8Array(value); }
    if (typeof value === 'string') { return utf8Encode(value); }
    return null;
  }

  function utf8Encode(text) {
    if (typeof TextEncoder !== 'undefined' && !global.__clashTextEncoder) {
      return new TextEncoder().encode(text);
    }
    return utf8EncodeSlow(text);
  }

  function utf8EncodeSlow(text) {
    var out = [];
    for (var i = 0; i < text.length; i++) {
      var code = text.charCodeAt(i);
      if (code < 0x80) { out.push(code); }
      else if (code < 0x800) { out.push(0xc0 | (code >> 6), 0x80 | (code & 63)); }
      else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
        var next = text.charCodeAt(i + 1);
        if (next >= 0xdc00 && next <= 0xdfff) {
          var point = 0x10000 + ((code - 0xd800) << 10) + (next - 0xdc00);
          out.push(0xf0 | (point >> 18), 0x80 | ((point >> 12) & 63),
                   0x80 | ((point >> 6) & 63), 0x80 | (point & 63));
          i++;
        } else { out.push(0xef, 0xbf, 0xbd); }
      } else if (code >= 0xdc00 && code <= 0xdfff) { out.push(0xef, 0xbf, 0xbd); }
      else { out.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63)); }
    }
    return new Uint8Array(out);
  }

  function utf8Decode(bytes) {
    if (typeof TextDecoder !== 'undefined' && !global.__clashTextDecoder) {
      try { return new TextDecoder('utf-8').decode(bytes); } catch (e) { /* fall through */ }
    }
    return utf8DecodeSlow(bytes);
  }

  function utf8DecodeSlow(bytes) {
    var out = '';
    for (var i = 0; i < bytes.length;) {
      var byte = bytes[i++];
      if (byte < 0x80) { out += String.fromCharCode(byte); }
      else if (byte < 0xe0) { out += String.fromCharCode(((byte & 31) << 6) | (bytes[i++] & 63)); }
      else if (byte < 0xf0) {
        out += String.fromCharCode(((byte & 15) << 12) | ((bytes[i++] & 63) << 6) | (bytes[i++] & 63));
      } else {
        var point = ((byte & 7) << 18) | ((bytes[i++] & 63) << 12) | ((bytes[i++] & 63) << 6) | (bytes[i++] & 63);
        point -= 0x10000;
        out += String.fromCharCode(0xd800 + (point >> 10), 0xdc00 + (point & 1023));
      }
    }
    return out;
  }

  function base64Encode(bytes) {
    var alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    var out = '';
    for (var i = 0; i < bytes.length; i += 3) {
      var a = bytes[i], b = bytes[i + 1], c = bytes[i + 2];
      out += alphabet[a >> 2];
      out += alphabet[((a & 3) << 4) | (b === undefined ? 0 : b >> 4)];
      out += b === undefined ? '=' : alphabet[((b & 15) << 2) | (c === undefined ? 0 : c >> 6)];
      out += c === undefined ? '=' : alphabet[c & 63];
    }
    return out;
  }

  function base64Decode(text) {
    var alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    var clean = String(text).replace(/[^A-Za-z0-9+/=]/g, '');
    var out = [];
    for (var i = 0; i < clean.length; i += 4) {
      var a = alphabet.indexOf(clean[i]), b = alphabet.indexOf(clean[i + 1]);
      var c = alphabet.indexOf(clean[i + 2]), d = alphabet.indexOf(clean[i + 3]);
      out.push((a << 2) | (b >> 4));
      if (c >= 0) { out.push(((b & 15) << 4) | (c >> 2)); }
      if (d >= 0) { out.push(((c & 3) << 6) | d); }
    }
    return new Uint8Array(out);
  }

  // Bytes cross the host boundary as `{"$clashBytes": "<base64>"}`. Only bodies
  // and explicitly binary API results take this path.
  function schemeOf(url) {
    var match = /^([a-zA-Z][a-zA-Z0-9+.-]*):/.exec(url || '');
    return match ? match[1].toLowerCase() : '';
  }

  function pathOf(url) {
    var rest = String(url || '').replace(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//, '');
    var slash = rest.indexOf('/');
    return slash < 0 ? '/' : rest.slice(slash);
  }

  function wireBytes(bytes) {
    if (!bytes) { return null; }
    return { $clashBytes: base64Encode(bytes) };
  }

  function unwireBytes(value) {
    if (value && typeof value === 'object' && typeof value.$clashBytes === 'string') {
      return base64Decode(value.$clashBytes);
    }
    return value;
  }

  // ---------------------------------------------------------------------------
  // Standard globals the engine does not have
  //
  // JavaScriptCore implements ECMAScript and nothing else: there is no `URL`,
  // no `URLSearchParams`, no `TextEncoder`/`TextDecoder` and no `atob`/`btoa`.
  // Rewrite scripts use all of them — `new URL($request.url).pathname` is the
  // most common line in the whole corpus — so they are provided here rather
  // than being a surprise at run time. Each is only defined when absent.

  function installStandardGlobals() {
    if (typeof global.TextEncoder === 'undefined') {
      global.TextEncoder = function TextEncoder() {};
      global.TextEncoder.prototype.encode = function (text) { return utf8EncodeSlow(String(text)); };
      global.__clashTextEncoder = true;
    }
    if (typeof global.TextDecoder === 'undefined') {
      global.TextDecoder = function TextDecoder() {};
      global.__clashTextDecoder = true;
      global.TextDecoder.prototype.decode = function (bytes) {
        return utf8DecodeSlow(bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes || []));
      };
    }
    if (typeof global.btoa === 'undefined') {
      global.btoa = function (text) { return base64Encode(utf8EncodeSlow(String(text))); };
    }
    if (typeof global.atob === 'undefined') {
      global.atob = function (text) { return utf8DecodeSlow(base64Decode(String(text))); };
    }
    if (typeof global.URL !== 'undefined') { return; }
    // A URL good enough for what scripts ask it: the parts, the search params,
    // and the ability to rebuild a string. Relative references resolve against
    // the script's own request URL, which is what a script means by them.
    function URLClass(input, base) {
      var text = String(input === undefined ? '' : input);
      var absolute = /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(text);
      if (!absolute && base !== undefined) {
        text = resolveURL(String(base), text);
      }
      var m = /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/([^\/?#]*)([^?#]*)(\?[^#]*)?(#.*)?$/.exec(text);
      this.href = text;
      this.protocol = m ? m[1] + ':' : '';
      this.host = m ? m[2] : '';
      var at = this.host.lastIndexOf('@');
      this.username = '';
      this.password = '';
      var hostPart = this.host;
      if (at >= 0) {
        var auth = this.host.slice(0, at).split(':');
        this.username = auth[0] || '';
        this.password = auth[1] || '';
        hostPart = this.host.slice(at + 1);
      }
      var colon = hostPart.lastIndexOf(':');
      var hasPort = colon >= 0 && /^[0-9]*$/.test(hostPart.slice(colon + 1));
      this.hostname = hasPort ? hostPart.slice(0, colon) : hostPart;
      this.port = hasPort ? hostPart.slice(colon + 1) : '';
      this.pathname = m ? (m[3] || '/') : '';
      this.search = m && m[4] ? m[4] : '';
      this.hash = m && m[5] ? m[5] : '';
      this.origin = this.protocol + '//' + this.host;
      this.searchParams = new URLSearchParamsClass(this.search.replace(/^\?/, ''));
    }
    URLClass.prototype.toString = function () { return this.href; };
    URLClass.prototype.toJSON = function () { return this.href; };
    global.URL = URLClass;

    function URLSearchParamsClass(init) {
      var pairs = parsePairs(init);
      var self = this;
      function refresh() {
        self._pairs = pairs;
        self._text = pairs.map(function (p) {
          return encodeURIComponent(p[0]) + '=' + encodeURIComponent(p[1]);
        }).join('&');
      }
      this.get = function (name) {
        for (var i = 0; i < pairs.length; i++) { if (pairs[i][0] === name) { return pairs[i][1]; } }
        return null;
      };
      this.getAll = function (name) {
        var out = [];
        for (var i = 0; i < pairs.length; i++) { if (pairs[i][0] === name) { out.push(pairs[i][1]); } }
        return out;
      };
      this.has = function (name) { return self.get(name) !== null; };
      this.set = function (name, value) {
        var found = false;
        for (var i = 0; i < pairs.length; i++) {
          if (pairs[i][0] === name) { pairs[i][1] = String(value); found = true; break; }
        }
        if (!found) { pairs.push([name, String(value)]); }
        refresh();
      };
      this.append = function (name, value) { pairs.push([name, String(value)]); refresh(); };
      this.delete = function (name) {
        pairs = pairs.filter(function (p) { return p[0] !== name; });
        refresh();
      };
      this.keys = function () { return pairs.map(function (p) { return p[0]; }); };
      this.values = function () { return pairs.map(function (p) { return p[1]; }); };
      this.entries = function () { return pairs.slice(); };
      this.forEach = function (fn) {
        for (var i = 0; i < pairs.length; i++) { fn(pairs[i][1], pairs[i][0], self); }
      };
      this.toString = function () { return self._text || ''; };
      refresh();
    }
    global.URLSearchParams = URLSearchParamsClass;

    function parsePairs(init) {
      var out = [];
      if (init === undefined || init === null || init === '') { return out; }
      if (typeof init === 'string') {
        var source = init.replace(/^\?/, '');
        if (!source) { return out; }
        source.split('&').forEach(function (item) {
          if (!item) { return; }
          var eq = item.indexOf('=');
          var key = eq < 0 ? item : item.slice(0, eq);
          var value = eq < 0 ? '' : item.slice(eq + 1);
          out.push([safeDecode(key), safeDecode(value)]);
        });
        return out;
      }
      if (typeof init === 'object') {
        if (Array.isArray(init)) {
          init.forEach(function (pair) { out.push([String(pair[0]), String(pair[1])]); });
        } else {
          for (var key in init) {
            if (Object.prototype.hasOwnProperty.call(init, key)) { out.push([key, String(init[key])]); }
          }
        }
      }
      return out;
    }

    function safeDecode(text) {
      try { return decodeURIComponent(String(text).replace(/\+/g, ' ')); }
      catch (e) { return String(text); }
    }

    function resolveURL(base, reference) {
      if (reference.charAt(0) === '#') { return base.replace(/#.*$/, '') + reference; }
      if (reference.charAt(0) === '?') { return base.replace(/[?#].*$/, '') + reference; }
      var baseMatch = /^([a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^\/]*)([^?#]*)/.exec(base);
      if (!baseMatch) { return reference; }
      var path = reference.charAt(0) === '/'
        ? reference
        : baseMatch[2].replace(/[^\/]*$/, '') + reference;
      // Collapse `.` and `..` the way a real resolver does.
      var parts = path.split('/');
      var out = [];
      for (var i = 0; i < parts.length; i++) {
        if (parts[i] === '.') { if (i === parts.length - 1) { out.push(''); } continue; }
        if (parts[i] === '..') { if (out.length > 1) { out.pop(); } if (i === parts.length - 1) { out.push(''); } continue; }
        out.push(parts[i]);
      }
      return baseMatch[1] + out.join('/');
    }
  }

  installStandardGlobals();

  // The three forms a plugin can write, restored as written.
  function argumentValue(kind, text, values) {
    if (kind === 'text') { return text === undefined || text === null ? '' : String(text); }
    if (kind === 'values') { return values || {}; }
    // Reached only if a caller asks for the value of a declaration that has
    // none. `install` leaves the global off in that case; `undefined` keeps
    // this helper honest rather than handing back a `null` that passes a
    // `typeof` guard.
    return undefined;
  }

  // ---------------------------------------------------------------------------
  // Logging

  function stringify(value) {
    if (value instanceof Uint8Array) {
      return 'Uint8Array(' + value.length + ') [' + Array.prototype.join.call(value, ', ') + ']';
    }
    if (typeof value === 'string') { return value; }
    if (value instanceof Error) { return value.stack || (value.name + ': ' + value.message); }
    try { return JSON.stringify(value); } catch (e) { return String(value); }
  }

  function logAt(level) {
    return function () {
      var parts = [];
      for (var i = 0; i < arguments.length; i++) { parts.push(stringify(arguments[i])); }
      logNative(parts.join(' '), level);
    };
  }

  global.console = {
    log: logAt('info'), info: logAt('info'), warn: logAt('warning'),
    error: logAt('error'), debug: logAt('debug'),
    group: logAt('info'), groupEnd: function () {}, time: function () {}, timeEnd: function () {}
  };

  // ---------------------------------------------------------------------------
  // Timers
  //
  // The host owns the clock. A timer that outlives the run is dropped with the
  // run, which is what the platforms do too.

  global.setTimeout = function (fn, delay) {
    var args = Array.prototype.slice.call(arguments, 2);
    var id = state.nextTimer++;
    state.timers[id] = { fn: fn, args: args };
    timerNative(Math.max(0, Number(delay) || 0), id);
    return id;
  };
  global.setInterval = function (fn, delay) {
    var args = Array.prototype.slice.call(arguments, 2);
    var period = Math.max(1, Number(delay) || 1);
    var id = state.nextTimer++;
    state.timers[id] = {
      fn: function () {
        if (!state.timers[id]) { return; }
        try { fn.apply(null, args); } catch (e) { logNative('script interval threw: ' + e, 'error'); }
        if (state.timers[id]) { timerNative(period, id); }
      },
      args: []
    };
    timerNative(period, id);
    return id;
  };
  global.clearTimeout = function (id) {
    delete state.timers[id];
    cancelNative(id);
  };
  global.clearInterval = global.clearTimeout;

  global.__clashResolve = function (id, answerJSON, error) {
    var callback = state.callbacks[id];
    if (!callback) { return; }
    delete state.callbacks[id];
    var answer = null;
    try { answer = JSON.parse(answerJSON); } catch (e) { answer = null; }
    try { callback(error || null, answer); } catch (e) {
      logNative('script callback threw: ' + (e && e.message ? e.message : e), 'error');
    }
  };

  global.__clashFireTimer = function (id) {
    var entry = state.timers[id];
    if (!entry) { return; }
    delete state.timers[id];
    try { entry.fn.apply(null, entry.args); } catch (e) {
      logNative('script timer threw: ' + (e && e.message ? e.message : e), 'error');
    }
  };

  // ---------------------------------------------------------------------------
  // Fetch-style HTTP
  //
  // Quantumult X's `$task.fetch` returns a Promise; everything else uses
  // `$httpClient`. Both are built on the same primitive, so a script that
  // reaches for either one gets the same routing and the same byte handling.

  function requestOptions(input, extra) {
    if (typeof input === 'string') { input = { url: input }; }
    var options = {};
    if (extra) { for (var key in extra) { if (Object.prototype.hasOwnProperty.call(extra, key)) { options[key] = extra[key]; } } }
    for (var own in input) { if (Object.prototype.hasOwnProperty.call(input, own)) { options[own] = input[own]; } }
    if (!options.method) { options.method = (options.body !== undefined || options.bodyBytes !== undefined) ? 'POST' : 'GET'; }
    options.method = String(options.method).toUpperCase();
    return options;
  }

  function encodeRequestBody(options) {
    if (options.bodyBytes !== undefined && options.bodyBytes !== null) {
      return wireBytes(toBytes(options.bodyBytes));
    }
    if (options.body === undefined || options.body === null) { return null; }
    if (typeof options.body === 'string') { return options.body; }
    if (options.body instanceof Uint8Array ||
        (typeof ArrayBuffer !== 'undefined' && (options.body instanceof ArrayBuffer || ArrayBuffer.isView(options.body)))) {
      return wireBytes(toBytes(options.body));
    }
    // An object body is JSON on every platform, with the header set for you.
    if (!options.headers) { options.headers = {}; }
    var hasType = false;
    for (var name in options.headers) {
      if (Object.prototype.hasOwnProperty.call(options.headers, name) && name.toLowerCase() === 'content-type') { hasType = true; }
    }
    if (!hasType) { options.headers['Content-Type'] = 'application/json'; }
    return JSON.stringify(options.body);
  }

  function performRequest(options, callback) {
    var body = encodeRequestBody(options);
    var timeout = Number(options.timeout);
    if (!isFinite(timeout) || timeout <= 0) { timeout = 5000; }
    // Loon and Quantumult X take milliseconds; Surge and Stash take seconds.
    if (state.platform === 'surge' || state.platform === 'stash') {
      timeout = timeout > 1000 ? timeout / 1000 : timeout;
    } else if (timeout <= 1000) {
      // Small numbers are the common case in scripts written for Surge and
      // pasted into Loon: treat them as seconds there too.
      timeout = timeout * 1000;
    }
    hostNative('http', JSON.stringify({
      url: options.url,
      method: options.method,
      headers: options.headers || {},
      body: body,
      timeout: timeout,
      binaryMode: options['binary-mode'] === true || options.binaryMode === true,
      insecure: options.insecure === true,
      autoRedirect: options['auto-redirect'] !== false,
      policy: options.policy || options.node || null
    }), nextCallback(function (error, answer) {
      if (error) { return callback(error, null, null); }
      var bytes = null;
      if (answer && answer.bodyBytes) { bytes = unwireBytes(answer.bodyBytes); }
      var data = bytes ? bytes : (answer ? answer.body : null);
      var response = answer ? {
        status: answer.status,
        statusCode: answer.status,
        headers: answer.headers || {},
        body: data,
        bodyBytes: bytes || undefined
      } : null;
      callback(null, response, data);
    }));
  }

  function nextCallback(fn) {
    var id = state.nextCallback++;
    state.callbacks[id] = fn;
    return id;
  }

  function makeHTTPClient() {
    var client = {};
    ['get', 'post', 'put', 'delete', 'head', 'options', 'patch'].forEach(function (method) {
      client[method] = function (input, callback) {
        var options = requestOptions(input);
        options.method = method.toUpperCase();
        performRequest(options, callback);
      };
    });
    // Some scripts call `$httpClient(options)` with the method inside.
    client.request = function (input, callback) { performRequest(requestOptions(input), callback); };
    return client;
  }

  function fetchPromise(input, extra) {
    return new Promise(function (resolve, reject) {
      performRequest(requestOptions(input, extra), function (error, response, data) {
        if (error) { reject({ error: error }); return; }
        var out = {
          status: response.status,
          statusCode: response.status,
          headers: response.headers,
          body: data,
          bodyBytes: response.bodyBytes
        };
        out.ok = response.status >= 200 && response.status < 300;
        out.statusText = '';
        resolve(out);
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Storage and local facts
  //
  // Every host names the same operations differently, but all of them answer
  // synchronously: storage is local on all four platforms, so a script may read
  // at the top of a file and use the value three lines later.

  // Loon documents the key as optional: "省略 Key 时使用 $script.name 作为默认
  // Key". Resolving it here rather than on the host keeps the contract in one
  // place — the host is handed a key or nothing, and never has to know the
  // script's name.
  function resolvedKey(key) {
    if (key === undefined || key === null) {
      var name = state.scriptName;
      return (name === undefined || name === null || name === '') ? null : String(name);
    }
    return String(key);
  }

  function read(key) {
    var answer = callNative('store.read', JSON.stringify({ key: resolvedKey(key) }));
    try { return JSON.parse(answer); } catch (e) { return null; }
  }

  function write(value, key, all) {
    var answer = callNative('store.write', JSON.stringify({
      key: resolvedKey(key),
      value: value === undefined || value === null ? null : String(value),
      all: all === true
    }));
    try { return JSON.parse(answer) === true; } catch (e) { return false; }
  }

  function local(name, payload) {
    var answer = callNative(name, JSON.stringify(payload === undefined ? null : payload));
    try { return JSON.parse(answer); } catch (e) { return null; }
  }

  // ---------------------------------------------------------------------------
  // Notifications

  function notify(title, subtitle, body, options, delay) {
    // Loon accepts a plain string as `attach`, meaning the URL to open.
    var content = {};
    if (typeof options === 'string') { content.openUrl = options; }
    else if (options && typeof options === 'object') {
      content.openUrl = options.openUrl || options['open-url'] || options.url || options.open;
      content.mediaUrl = options.mediaUrl || options['media-url'] || options.media;
      content.clipboard = options.clipboard || options.copy || options['update-pasteboard'];
      if (options['auto-dismiss'] !== undefined) { content.autoDismiss = !!options['auto-dismiss']; }
      if (options.sound !== undefined) { content.sound = !!options.sound; }
    }
    if (delay) { content.delay = Number(delay) || 0; }
    hostNative('notify', JSON.stringify({
      title: title === undefined ? '' : String(title),
      subtitle: subtitle === undefined ? '' : String(subtitle),
      body: body === undefined ? '' : String(body),
      openUrl: content.openUrl || null,
      mediaUrl: content.mediaUrl || null,
      clipboard: content.clipboard || null,
      autoDismiss: content.autoDismiss === undefined ? null : content.autoDismiss,
      sound: content.sound === undefined ? null : content.sound
    }), -1);
  }

  // ---------------------------------------------------------------------------
  // $done
  //
  // One entry point for every platform. The host reads the same shape from all
  // of them and decides, by phase, whether a returned response is a mock or a
  // rewrite. `status` may be a number or a status line; the host parses both.

  function done(payload) {
    if (state.done) { return; }
    state.done = true;
    if (typeof payload === 'string') { payload = { body: payload }; }
    var out = (payload === null || payload === undefined) ? {} : payload;
    hostNative('done', JSON.stringify(normalizeDone(out)), -1);
  }

  function withPath(path) {
    var match = /^([a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^\/]+)(.*)$/.exec(state.requestURL || '');
    if (!match) { return path; }
    return match[1] + (path.charAt(0) === '/' ? path : '/' + path);
  }

  function normalizeDone(payload) {
    var out = {};
    for (var key in payload) {
      if (!Object.prototype.hasOwnProperty.call(payload, key)) { continue; }
      var value = payload[key];
      if (value === undefined) { continue; }
      if (key === 'body' || key === 'bodyBytes') {
        out[key] = typeof value === 'string' ? value : wireBytes(toBytes(value));
      } else if (key === 'path' && typeof value === 'string') {
        // Quantumult X's own scripts rewrite `$done({path: ...})`; the host
        // rebuilds the URL from it rather than handing the script a full URL.
        out.url = withPath(value);
      } else if (key === 'response' && value && typeof value === 'object') {
        out.response = normalizeDone(value);
      } else if (key === 'headers' && value && typeof value === 'object') {
        var headers = {};
        for (var name in value) {
          if (Object.prototype.hasOwnProperty.call(value, name) && value[name] !== undefined) {
            headers[name] = String(value[name]);
          }
        }
        out.headers = headers;
      } else {
        out[key] = value;
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // JSBox
  //
  // JSBox's API is Promise based and names its fields differently; a JSBox
  // script reaches for `$http`, `$cache` and `$push`.

  function jsboxHTTP(options) {
    return new Promise(function (resolve, reject) {
      if (typeof options === 'string') { options = { url: options }; }
      performRequest({
        url: options.url,
        method: options.method || 'GET',
        headers: options.header || options.headers || {},
        body: options.body,
        timeout: options.timeout || 5000
      }, function (error, response, data) {
        if (error) { reject(error); return; }
        resolve({ data: data, response: { status: response.status, headers: response.headers } });
      });
    });
  }

  function jsboxCache() {
    return {
      get: function (key) { return read(key); },
      set: function (key, value) { return write(value, key); },
      remove: function (key) { return write(null, key); }
    };
  }

  // ---------------------------------------------------------------------------
  // Installing a platform
  //
  // Only the chosen platform's globals exist. `$environment` is defined for the
  // platforms that document it, and never with another platform's version key:
  // Env.js reads `surge-version` and `stash-version` before it looks at `$loon`.

  var doneAliases = {};

  function install(payload) {
    var platform = payload.platform;

    global.$script = {
      name: payload.scriptName || '',
      type: state.phase,
      // Loon hands out a Date and Surge a number of seconds; scripts subtract
      // whichever they expect from `new Date()` or `Date.now()`.
      startTime: platform === 'loon' ? new Date(state.started) : state.started / 1000,
      sessionID: 'clash'
    };
    if (state.binaryBody) { global.$script.binaryBodyMode = true; }

    global.$request = payload.request;
    global.$response = payload.response;
    global.$done = done;
    // `$argument` is whatever the plugin wrote in its `script(...)` line: a
    // string (`script("x.js", "a=1&b=2")`), an object of the plugin's own
    // `[Argument]` values (`script("x.js", {${a}, ${b}})`, values keeping their
    // declared type), or nothing at all when the second argument is omitted.
    // Scripts read the string with `.split('&')` and the object by name, and
    // neither form is safe to substitute for the other.
    //
    // A declaration with no argument installs **no** `$argument` rather than a
    // `null` one. Surge documents the global as "only present if the parameter
    // is configured", and the scripts rely on that: their guard is
    // `typeof $argument != 'undefined'`, which a `null` value passes — and then
    // the very next line calls `.split()` on it. Nine scripts in the hub's own
    // corpus crash exactly there.
    if (payload.argumentKind !== 'none') {
      global.$argument = argumentValue(payload.argumentKind, payload.argumentText, state.argument);
    }

    if (platform === 'quantumultX') {
      // Quantumult X: $task, $prefs, $notify, $environment.variables.
      global.$task = {
        fetch: function (input, extra) { return fetchPromise(input, extra); }
      };
      global.$prefs = {
        valueForKey: function (key) { return read(key); },
        setValueForKey: function (value, key) { return write(value, key); },
        removeValueForKey: function (key) { return write(null, key); },
        removeAllValues: function () { return write(null, null, true); }
      };
      global.$notify = function (title, subtitle, body, options) {
        notify(title, subtitle, body, options);
      };
      global.$environment = { app: 'Quantumult X', variables: state.argument };
    } else if (platform === 'jsbox') {
      global.$http = jsboxHTTP;
      global.$cache = jsboxCache();
      global.$push = function (payloadObject) {
        notify((payloadObject && payloadObject.title) || 'JSBox', '', (payloadObject && payloadObject.body) || '', {});
      };
      global.$environment = { app: payload.appName };
    } else {
      // Surge, Loon, Stash and Shadowrocket share $httpClient, $persistentStore,
      // $notification and $utils; they differ in their identity globals.
      global.$httpClient = makeHTTPClient();
      global.$persistentStore = {
        read: function (key) { return read(key); },
        write: function (value, key) { return write(value, key); },
        remove: function () { return write(null, null, true); }
      };
      global.$notification = {
        post: function (title, subtitle, body, options, delay) {
          notify(title, subtitle, body, options, delay);
        }
      };
      global.$utils = {
        geoip: function (ip) { return local('utils.geoip', { ip: ip }); },
        ipasn: function (ip) { return local('utils.ipasn', { ip: ip }); },
        ipaso: function (ip) { return local('utils.ipaso', { ip: ip }); },
        gzip: function (bytes) { return unwireBytes(local('utils.gzip', { data: wireBytes(toBytes(bytes)) })); },
        ungzip: function (bytes) { return unwireBytes(local('utils.ungzip', { data: wireBytes(toBytes(bytes)) })); }
      };
      global.$crypto = {
        aes: {
          encrypt: function (data, options) { return unwireBytes(local('crypto.aes.encrypt', aesPayload(data, options))); },
          decrypt: function (data, options) { return unwireBytes(local('crypto.aes.decrypt', aesPayload(data, options))); }
        }
      };
      global.$dns = {
        query: function (options, callback) {
          hostNative('dns.query', JSON.stringify(options || {}), nextCallback(function (error, answer) {
            callback(error, answer);
          }));
        }
      };
      global.$config = {
        getConfig: function () { return local('config.getConfig', {}); },
        getSelectedPolicy: function (group) { return local('config.getSelectedPolicy', { group: group }); },
        getPolicy: function (group) { return local('config.getSelectedPolicy', { group: group }); },
        setSelectPolicy: function (group, policy) { return local('config.setSelectPolicy', { group: group, policy: policy }); },
        setRunningModel: function (model) { return local('config.setRunningModel', { model: model }); },
        getSubPolicies: function (group, callback) {
          hostNative('config.getSubPolicies', JSON.stringify({ group: group }), nextCallback(function (error, answer) {
            callback(error ? null : JSON.stringify(answer || []));
          }));
        },
        getSubPolicys: function (group, callback) { global.$config.getSubPolicies(group, callback); }
      };
    }

    if (platform === 'loon') {
      // Loon: a bare version string, and `$environment` carrying the run
      // parameters when the script was started from a node or policy.
      //
      // Loon's manual, §3.4: "没有运行参数时，`$environment` 可能不存在", and the
      // example it gives guards with `typeof $environment === "undefined"`. So
      // the global is left off when there is nothing to report — an empty
      // `{ params: {} }` would answer `params.node` with `undefined` instead,
      // which is not the same thing to a script that tests for the global.
      global.$loon = payload.loon;
      if (payload.parameters) {
        // Two shapes, because scripts disagree and Loon changed its mind:
        // `NodeLinkCheck.js` treats `params` as the node name string — it calls
        // `$environment.params.search(/IEPL/gi)` and concatenates the value into
        // HTML — while `NodeUnlockDetection.js` reads `params.node`.
        //
        // The object is the current form, so it is what `params` is. The old
        // string form is reachable two ways that cost nothing: `params.entry`
        // for a script written for it, and `toString`/`search`/`indexOf` so a
        // script that treats the whole value as a string still works instead of
        // throwing `params.search is not a function`.
        var params = payload.parameters;
        var entry = payload.parameterEntry;
        if (entry !== undefined && entry !== null) {
          params.entry = entry;
          params.toString = function () { return entry; };
          params.valueOf = function () { return entry; };
          params.search = function (pattern) { return entry.search(pattern); };
          params.indexOf = function (needle, from) { return entry.indexOf(needle, from); };
          params.match = function (pattern) { return entry.match(pattern); };
        }
        global.$environment = { params: params };
      }
    } else if (platform === 'shadowrocket') {
      global.$rocket = { version: payload.version, device: payload.device };
    } else if (platform === 'surge' || platform === 'stash') {
      var environment = {
        system: payload.systemVersion,
        language: 'zh-Hans',
        'device-model': payload.device,
        app: payload.appName
      };
      if (platform === 'surge') {
        environment['surge-version'] = payload.version;
        environment['surge-build'] = String(payload.version).replace(/[^0-9]/g, '').slice(0, 6) || '2000';
      } else {
        environment['stash-version'] = payload.version;
      }
      global.$environment = environment;
      if (platform === 'surge') {
        global.$surge = {
          setSelectGroupPolicy: function (group, policy) {
            return local('config.setSelectPolicy', { group: group, policy: policy }) === true;
          },
          setOutboundMode: function (mode) {
            return local('config.setRunningModel', { model: mode }) === true;
          },
          selectGroupDetails: function () { return local('config.selectGroupDetails', {}) || {}; }
        };
      }
      // Surge and Stash also answer to $loon-shaped `$script`, already set.
      global.$script.type = state.phase;
    }
  }

  function aesPayload(data, options) {
    options = options || {};
    return {
      data: wireBytes(toBytes(data)),
      mode: options.mode,
      key: wireBytes(toBytes(options.key)),
      iv: wireBytes(toBytes(options.iv)),
      padding: options.padding,
      aad: wireBytes(toBytes(options.aad)),
      tag: wireBytes(toBytes(options.tag))
    };
  }

  // ---------------------------------------------------------------------------
  // Entry point the host calls

  global.__clashBootstrap = function (payload) {
    state.platform = payload.platform;
    state.phase = payload.phase || 'request';
    state.argument = payload.argument || {};
    state.binaryBody = payload.binaryBody === true;
    // Loon's storage key defaults to `$script.name` when a script omits it.
    state.scriptName = payload.scriptName;
    state.requestURL = payload.request ? payload.request.url : '';

    var request = null, response = null;
    if (payload.request) {
      request = {
        url: payload.request.url,
        method: payload.request.method,
        headers: payload.request.headers || {},
        h2_trailers: {}
      };
      // Quantumult X exposes these and no other platform does; a script
      // published for it reaches for them unguarded.
      if (payload.platform === 'quantumultX') {
        request.scheme = schemeOf(request.url);
        request.path = pathOf(request.url);
      };
      if (payload.request.body !== undefined && payload.request.body !== null) {
        var bytes = unwireBytes(payload.request.body);
        request.body = state.binaryBody ? bytes : utf8Decode(bytes);
        // Surge, Loon and Stash all expose the raw bytes as `bodyBytes` in
        // binary-body-mode, and scripts read that rather than `body`. It is
        // the same bytes; the field is what makes a Protobuf or gRPC script
        // able to run at all.
        if (state.binaryBody) { request.bodyBytes = bytes; }
      }
    }
    if (payload.response) {
      response = {
        status: payload.response.status,
        statusCode: payload.response.status,
        headers: payload.response.headers || {},
        h2_trailers: {}
      };
      if (payload.platform === 'quantumultX') {
        response.headers = Object.assign({}, payload.response.headers || {});
      };
      if (payload.response.body !== undefined && payload.response.body !== null) {
        var resBytes = unwireBytes(payload.response.body);
        response.body = state.binaryBody ? resBytes : utf8Decode(resBytes);
        if (state.binaryBody) { response.bodyBytes = resBytes; }
      }
    }

    install({
      platform: payload.platform,
      argumentKind: payload.argumentKind,
      argumentText: payload.argumentText,
      version: payload.version,
      device: payload.device,
      systemVersion: payload.systemVersion,
      appName: payload.appName,
      loon: payload.loon,
      scriptName: payload.scriptName,
      // Loon's entry parameters, when the run had any. Left off rather than
      // passed as an empty object, because `install` decides whether
      // `$environment` exists at all from their presence.
      parameters: payload.parameters,
      parameterEntry: payload.parameterEntry,
      request: request,
      response: response
    });
  };

  // Namespaced so it cannot be mistaken for a platform global by any probe.
  global.__clash = {
    version: 1,
    platform: function () { return state.platform; },
    bytes: toBytes,
    text: utf8Decode
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
