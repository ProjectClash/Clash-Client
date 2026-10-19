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
    if (typeof TextEncoder !== 'undefined') { return new TextEncoder().encode(text); }
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
    if (typeof TextDecoder !== 'undefined') {
      try { return new TextDecoder('utf-8').decode(bytes); } catch (e) { /* fall through */ }
    }
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

  function read(key) {
    var answer = callNative('store.read', JSON.stringify({ key: key === undefined ? null : key }));
    try { return JSON.parse(answer); } catch (e) { return null; }
  }

  function write(value, key, all) {
    var answer = callNative('store.write', JSON.stringify({
      key: key === undefined ? null : key,
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

  function normalizeDone(payload) {
    var out = {};
    for (var key in payload) {
      if (!Object.prototype.hasOwnProperty.call(payload, key)) { continue; }
      var value = payload[key];
      if (value === undefined) { continue; }
      if (key === 'body' || key === 'bodyBytes') {
        out[key] = typeof value === 'string' ? value : wireBytes(toBytes(value));
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
    global.$argument = state.argument;

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
      global.$http = jsboxHTTP;
      global.$cache = jsboxCache();
      global.$push = function (payloadObject) {
        notify((payloadObject && payloadObject.title) || 'JSBox', '', (payloadObject && payloadObject.body) || '', {});
      };
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
      // Loon: a bare version string, and $environment carrying run parameters
      // for generic scripts only.
      global.$loon = payload.loon;
      global.$environment = { params: {} };
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

    var request = null, response = null;
    if (payload.request) {
      request = {
        url: payload.request.url,
        method: payload.request.method,
        headers: payload.request.headers || {},
        h2_trailers: {}
      };
      if (payload.request.body !== undefined && payload.request.body !== null) {
        var bytes = unwireBytes(payload.request.body);
        request.body = state.binaryBody ? bytes : utf8Decode(bytes);
      }
    }
    if (payload.response) {
      response = {
        status: payload.response.status,
        statusCode: payload.response.status,
        headers: payload.response.headers || {},
        h2_trailers: {}
      };
      if (payload.response.body !== undefined && payload.response.body !== null) {
        var resBytes = unwireBytes(payload.response.body);
        response.body = state.binaryBody ? resBytes : utf8Decode(resBytes);
      }
    }

    install({
      platform: payload.platform,
      version: payload.version,
      device: payload.device,
      systemVersion: payload.systemVersion,
      appName: payload.appName,
      loon: payload.loon,
      scriptName: payload.scriptName,
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
