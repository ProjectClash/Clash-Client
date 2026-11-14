#if os(iOS) || os(macOS)
import Foundation
import JavaScriptCore

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ModuleScriptQuantumultX {
    static func install(in context: JSContext, for session: ModuleScriptSession) {
        installPrefs(context, session)
        installNotify(context, session)
        installTask(context, session)
        installConfiguration(context, session)
    }

    private static func live(_ session: ModuleScriptSession?) -> ModuleScriptSession? { ModuleScriptGlobals.live(session) }

     

    static func installMessage(_ message: ModuleScriptHostRequest, in context: JSContext, for session: ModuleScriptSession) {
        let request = JSValue(newObjectIn: context)!
        request.setObject(message.url, forKeyedSubscript: "url" as NSString)
        request.setObject(message.method, forKeyedSubscript: "method" as NSString)
        request.setObject(ModuleScriptGlobals.headersObject(message.headers, in: context), forKeyedSubscript: "headers" as NSString)
        let parts = components(of: message.url)
        request.setObject(parts.scheme, forKeyedSubscript: "scheme" as NSString)
        request.setObject(parts.path, forKeyedSubscript: "path" as NSString)
        request.setObject(message.id, forKeyedSubscript: "sessionIndex" as NSString)
        if session.phase == .request { installBody(on: request, in: context, for: session) }
        context.setObject(request, forKeyedSubscript: "$request" as NSString)

        guard session.phase == .response, let response = session.response else { return }
        let object = JSValue(newObjectIn: context)!
        object.setObject(response.status, forKeyedSubscript: "statusCode" as NSString)
        object.setObject(ModuleScriptGlobals.headersObject(response.headers, in: context), forKeyedSubscript: "headers" as NSString)
        object.setObject(message.id, forKeyedSubscript: "sessionIndex" as NSString)
        installBody(on: object, in: context, for: session)
        context.setObject(object, forKeyedSubscript: "$response" as NSString)
    }

     
     
    static func components(of url: String) -> (scheme: String, path: String) {
        guard let parts = URLComponents(string: url) else { return ("", "") }
        let path = parts.percentEncodedPath.isEmpty ? "/" : parts.percentEncodedPath
        return (parts.scheme ?? "", parts.percentEncodedQuery.map { path + "?" + $0 } ?? path)
    }

     
     
     
     
     
    private static func installBody(on object: JSValue, in context: JSContext, for session: ModuleScriptSession) {
        guard session.declaration.requiresBody, let body = session.body, !body.isEmpty else { return }
        object.setObject(String(decoding: body, as: UTF8.self), forKeyedSubscript: "body" as NSString)
        let make: @convention(block) () -> Any = { [weak session] in
            guard live(session) != nil, let context = JSContext.current() else { return NSNull() }
            return ModuleScriptValues.uint8Array(body, in: context) ?? NSNull()
        }
        let installer = context.evaluateScript(#"""
        (function (target, make) {
          var made, read = false;
          Object.defineProperty(target, "bodyBytes", {
            enumerable: true, configurable: true,
            get: function () {
              if (!read) { read = true; var bytes = make(); made = bytes ? bytes.buffer : undefined; }
              return made;
            },
            set: function (value) { read = true; made = value; }
          });
        })
        """#)
        _ = installer?.call(withArguments: [object, ModuleScriptValues.function(make, in: context)])
    }

     

     
     
     
     
     
     
    private static func installPrefs(_ context: JSContext, _ session: ModuleScriptSession) {
        let owner = ModuleScriptStore.Owner(session.declaration)
        let read: @convention(block) (JSValue) -> Any = { [weak session] key in
            guard let session = live(session) else { return NSNull() }
            guard let name = ModuleScriptValues.string(key) else {
                session.log(#"$prefs.valueForKey: the key is not a string; null"#)
                return NSNull()
            }
            return session.store.read(key: name, by: owner) ?? NSNull()
        }
        let write: @convention(block) (JSValue, JSValue) -> Bool = { [weak session] value, key in
            guard let session = live(session) else { return false }
            guard let name = ModuleScriptValues.string(key) else {
                session.log(#"$prefs.setValueForKey: the key is not a string; false"#)
                return false
            }
             
            return session.store.write(ModuleScriptValues.isAbsent(value) ? nil : value.toString(), key: name, by: owner)
        }
        let remove: @convention(block) (JSValue) -> Bool = { [weak session] key in
            guard let session = live(session), let name = ModuleScriptValues.string(key) else { return false }
            return session.store.write(nil, key: name, by: owner)
        }
        let removeAll: @convention(block) () -> Bool = { [weak session] in
            live(session)?.store.remove() ?? false
        }
        let prefs = JSValue(newObjectIn: context)!
        prefs.setObject(read, forKeyedSubscript: "valueForKey" as NSString)
        prefs.setObject(write, forKeyedSubscript: "setValueForKey" as NSString)
        prefs.setObject(remove, forKeyedSubscript: "removeValueForKey" as NSString)
        prefs.setObject(removeAll, forKeyedSubscript: "removeAllValues" as NSString)
        context.setObject(prefs, forKeyedSubscript: "$prefs" as NSString)
    }

     

     
     
     
    private static func installNotify(_ context: JSContext, _ session: ModuleScriptSession) {
        let notify: @convention(block) () -> Void = { [weak session] in
            guard let session = live(session) else { return }
            let arguments = Array((JSContext.currentArguments() as? [JSValue] ?? []).prefix(4))
            _ = session.notify(ModuleScriptGlobals.notification(from: arguments, scriptName: session.declaration.name, log: session.log))
        }
        context.setObject(notify, forKeyedSubscript: "$notify" as NSString)
    }

     

     
     
     
     
     
     
    private static func installTask(_ context: JSContext, _ session: ModuleScriptSession) {
        let fetch: @convention(block) (JSValue, JSValue) -> Void = { [weak session] options, callback in
            guard let session = live(session) else { return }
            session.send(httpRequest(options), callback: ModuleScriptValues.isFunction(callback) ? callback : nil)
        }
        let installer = context.evaluateScript(#"""
        (function (fetch) {
          return {
            fetch: function (request) {
              return new Promise(function (resolve, reject) {
                fetch(request, function (error, response, body, bytes) {
                  if (error !== null && error !== undefined) { reject({ error: String(error) }); return; }
                  var answer = { statusCode: response.status, headers: response.headers, body: body };
                  if (bytes) { answer.bodyBytes = bytes.buffer; }
                  resolve(answer);
                });
              });
            }
          };
        })
        """#)
        if let task = installer?.call(withArguments: [ModuleScriptValues.function(fetch, in: context)]), task.isObject {
            context.setObject(task, forKeyedSubscript: "$task" as NSString)
        }
    }

     
     
    static let fetchTimeoutSeconds: Double = 10

     
     
     
     
     
     
    static func httpRequest(_ options: JSValue) -> ModuleScriptHTTPRequest {
        var request = ModuleScriptHTTPRequest(method: "GET", url: "", timeoutSeconds: fetchTimeoutSeconds, options: ["auto-cookie": "false"])
        if options.isString {
            request.url = options.toString() ?? ""
            return request
        }
        guard options.isObject else { return request }
        func field(_ name: String) -> JSValue? {
            guard let value = options.objectForKeyedSubscript(name), !ModuleScriptValues.isAbsent(value) else { return nil }
            return value
        }
        request.url = ModuleScriptValues.string(field("url")) ?? ""
        if let method = ModuleScriptValues.string(field("method")), !method.isEmpty { request.method = method.uppercased() }
        if let headers = field("headers"), headers.isObject, !headers.isArray {
            for name in ModuleScriptValues.propertyNames(of: headers) {
                guard let value = headers.objectForKeyedSubscript(name), !ModuleScriptValues.isAbsent(value) else { continue }
                request.headers.append(ModuleScriptHeader(name: name, value: value.toString() ?? ""))
            }
        }
        if let bytes = field("bodyBytes").flatMap({ ModuleScriptValues.bytes($0, textAllowed: false) }) {
            request.body = bytes
        } else if let body = field("body") {
            request.body = ModuleScriptValues.bytes(body, textAllowed: true) ?? Data(ModuleScriptValues.describe(body).utf8)
        }
        if let opts = field("opts"), opts.isObject {
            for name in ModuleScriptValues.propertyNames(of: opts) {
                guard let value = opts.objectForKeyedSubscript(name), !ModuleScriptValues.isAbsent(value) else { continue }
                switch name {
                case "redirection": request.options["auto-redirect"] = value.toBool() ? "true" : "false"
                case "skip-cert-verify": request.options["insecure"] = value.toBool() ? "true" : "false"
                case "auto-cookie": request.options["auto-cookie"] = value.toBool() ? "true" : "false"
                default: request.options[name] = ModuleScriptValues.describe(value)
                }
            }
        }
        return request
    }

     

     
     
     
    private static func installConfiguration(_ context: JSContext, _ session: ModuleScriptSession) {
        let send: @convention(block) (JSValue, JSValue) -> Void = { [weak session] message, resolve in
            guard let session = live(session) else { return }
            _ = session.addTimer(resolve, milliseconds: 0, arguments: [configurationAnswer(message, session: session)])
        }
        let installer = context.evaluateScript(#"""
        (function (send) {
          return {
            sendMessage: function (message) {
              return new Promise(function (resolve) { send(message, resolve); });
            }
          };
        })
        """#)
        if let configuration = installer?.call(withArguments: [ModuleScriptValues.function(send, in: context)]), configuration.isObject {
            context.setObject(configuration, forKeyedSubscript: "$configuration" as NSString)
        }
    }

     
     
     
     
    static func qxType(_ core: String) -> String? {
        switch core {
        case "Selector": return "static"
        case "URLTest", "Smart": return "url-latency-benchmark"
        case "Fallback": return "available"
        case "LoadBalance": return "round-robin"
        default: return nil
        }
    }

     
    static let runningModes = ["rule": "filter", "global": "all_proxy", "direct": "all_direct"]

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func configurationAnswer(_ message: JSValue, session: ModuleScriptSession) -> [String: Any] {
        let action = ModuleScriptValues.string(message.objectForKeyedSubscript("action")) ?? ""
        let content = message.objectForKeyedSubscript("content")
        let access = session.services.config
        func error(_ words: String) -> [String: Any] {
            session.log(#"$configuration.sendMessage(\#(action)): \#(words)"#)
            return ["error": words]
        }
        let known: Set<String> = ["get_policy_state", "set_policy_state", "get_customized_policy", "get_running_mode", "set_running_mode"]
        guard known.contains(action) else { return error(#"\#(action) is not available in Clash"#) }
        guard access.isAvailable() else { return error(#"no running configuration to read here"#) }
        func state() -> [String: Any] {
            let groups = access.groups()
            let names = Set(groups)
            var out: [String: Any] = [:]
            for group in groups {
                var chain = [group]
                while chain.count < 16, let selected = access.selected(chain[chain.count - 1]) {
                    chain.append(selected)
                    if !names.contains(selected) || chain.dropLast().contains(selected) { break }
                }
                out[group] = chain
            }
            return out
        }
        switch action {
        case "get_policy_state":
            return ["ret": state()]
        case "set_policy_state":
            guard let content, content.isObject, !content.isArray else { return error(#"content is an object of group and policy"#) }
            for group in ModuleScriptValues.propertyNames(of: content) {
                guard let policy = ModuleScriptValues.string(content.objectForKeyedSubscript(group)) else { continue }
                let taken = session.services.selectPolicy(group, policy)
                session.log(#"$configuration.sendMessage(set_policy_state) \#(group) -> \#(policy): \#(taken)"#)
            }
            return ["ret": state()]
        case "get_customized_policy":
            var names = access.groups()
            if let content, let one = ModuleScriptValues.string(content) {
                names = [one]
            } else if let content, content.isArray {
                names = (content.toArray() ?? []).compactMap { $0 as? String }
            }
            let types = access.groupTypes()
            var out: [String: Any] = [:]
            for name in names {
                guard let members = access.members(name, ModuleScriptGlobals.maximumSubPolicies) else { continue }
                var group: [String: Any] = ["candidates": members.map(\.name)]
                if let type = types[name].flatMap(qxType) { group["type"] = type }
                out[name] = group
            }
            return ["ret": out]
        case "get_running_mode":
            guard let mode = access.mode().flatMap({ runningModes[$0] }) else { return error(#"no running mode to read"#) }
            return ["ret": ["running_mode": mode]]
        default:
            let wanted = content.flatMap { ModuleScriptValues.string($0.objectForKeyedSubscript("running_mode")) }
            guard let mode = runningModes.first(where: { $0.value == wanted })?.key else {
                return error(#"running_mode is filter, all_proxy or all_direct"#)
            }
            if mode == #"global"#, let refusal = access.globalRefusal() {
                session.log(#"$configuration.sendMessage(set_running_mode) global: \#(refusal)"#)
                return error(refusal)
            }
            let changed = access.setMode(mode)
            session.log(#"$configuration.sendMessage(set_running_mode) \#(mode): \#(changed)"#)
            return changed ? ["ret": ["running_mode": runningModes[mode] ?? mode]] : error(#"the running mode was not changed"#)
        }
    }

     

     
     
    static func statusCode(_ value: JSValue?) -> Int? {
        guard let value, !ModuleScriptValues.isAbsent(value) else { return nil }
        if value.isNumber { return ModuleScriptValues.integer(value) }
        guard value.isString, let text = value.toString() else { return nil }
        let words = text.split(separator: " ")
        if let first = words.first, let number = Int(first) { return number }
        guard words.count >= 2, words[0].uppercased().hasPrefix("HTTP/"), let number = Int(words[1]) else { return nil }
        return number
    }

     
     
     
     
    static func url(_ url: String, withPath path: String) -> String? {
        guard let start = url.range(of: "://") else { return nil }
        let end = url[start.upperBound...].firstIndex { "/?#".contains($0) } ?? url.endIndex
        let made = String(url[..<end]) + (path.hasPrefix("/") ? path : "/" + path)
        guard let parsed = URL(string: made), parsed.host?.isEmpty == false else { return nil }
        return made
    }
}
#endif
