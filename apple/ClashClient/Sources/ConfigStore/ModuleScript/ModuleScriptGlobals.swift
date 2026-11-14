#if os(iOS) || os(macOS)
import Foundation
import JavaScriptCore

 
 
 
enum ModuleScriptGlobals {
     
     
     
     
     
     
    static func live(_ session: ModuleScriptSession?) -> ModuleScriptSession? {
        guard let session, session.isLive else { return nil }
        return session
    }

    static func install(in context: JSContext, for session: ModuleScriptSession) {
        installConsole(context, session)
        installTimers(context, session)
        installWebAssembly(context, session)
        installDone(context, session)
        installMessage(context, session)
        installIdentity(context, session)
         
         
        if session.declaration.family == .quantumultX {
            return ModuleScriptQuantumultX.install(in: context, for: session)
        }
        installStore(context, session)
        installUtils(context, session)
        installHTTPClient(context, session)
        installNotification(context, session)
        installSurge(context, session)
        installConfig(context, session)
        installDNS(context, session)
    }

    private static func installConsole(_ context: JSContext, _ session: ModuleScriptSession) {
        let write: @convention(block) () -> Void = { [weak session] in
             
             
            guard let session = live(session) else { return }
            let words = (JSContext.currentArguments() as? [JSValue] ?? []).map(ModuleScriptValues.describe)
            session.console(words.joined(separator: " "))
        }
        let console = JSValue(newObjectIn: context)!
        for name in ["log", "info", "warn", "error", "debug"] {
            console.setObject(write, forKeyedSubscript: name as NSString)
        }
        context.setObject(console, forKeyedSubscript: "console" as NSString)
    }

     
     
     
    private static func installTimers(_ context: JSContext, _ session: ModuleScriptSession) {
        let setTimeout: @convention(block) (JSValue, JSValue) -> Int = { [weak session] callback, delay in
            let extra = Array((JSContext.currentArguments() as? [JSValue] ?? []).dropFirst(2))
            return live(session)?.addTimer(callback, milliseconds: delay.isNumber ? delay.toDouble() : 0, arguments: extra) ?? 0
        }
        let setInterval: @convention(block) (JSValue, JSValue) -> Int = { [weak session] callback, delay in
            let extra = Array((JSContext.currentArguments() as? [JSValue] ?? []).dropFirst(2))
            return live(session)?.addTimer(callback, milliseconds: delay.isNumber ? delay.toDouble() : 0, arguments: extra,
                                     repeating: true) ?? 0
        }
         
        let clear: @convention(block) (JSValue) -> Void = { [weak session] id in
            if id.isNumber { live(session)?.clearTimer(Int(id.toInt32())) }
        }
        context.setObject(setTimeout, forKeyedSubscript: "setTimeout" as NSString)
        context.setObject(setInterval, forKeyedSubscript: "setInterval" as NSString)
        context.setObject(clear, forKeyedSubscript: "clearTimeout" as NSString)
        context.setObject(clear, forKeyedSubscript: "clearInterval" as NSString)
        installQueueMicrotask(context, session)
    }

     
     
     
     
     
    private static func installQueueMicrotask(_ context: JSContext, _ session: ModuleScriptSession) {
        let report: @convention(block) (JSValue) -> Void = { [weak session] exception in
            live(session)?.reportUncaught(exception)
        }
        let installer = context.evaluateScript(#"""
        (function (report) {
          globalThis.queueMicrotask = function queueMicrotask(callback) {
            if (typeof callback !== "function") {
              throw new TypeError("queueMicrotask: the argument is not a function");
            }
            Promise.resolve().then(function () {
              try { callback(); } catch (error) { report(error); }
            });
          };
        })
        """#)
        _ = installer?.call(withArguments: [ModuleScriptValues.function(report, in: context)])
    }

     
     
     
     
     
    static let webAssemblyAsyncCalls = ["compile", "instantiate", "compileStreaming", "instantiateStreaming"]

    private static func installWebAssembly(_ context: JSContext, _ session: ModuleScriptSession) {
        let began: @convention(block) () -> Bool = { [weak session] in live(session)?.engineWorkBegan() ?? false }
        let settled: @convention(block) () -> Void = { [weak session] in live(session)?.engineWorkSettled() }
        let installer = context.evaluateScript(#"""
        (function (began, settled, names) {
          var W = globalThis.WebAssembly;
          if (typeof W !== "object" || W === null) return;
          names.forEach(function (name) {
            var original = W[name];
            if (typeof original !== "function") return;
            W[name] = function () {
              // A run that may reach nothing compiles nothing: its promise
              // never settles, and nothing turns for it.
              if (!began()) return new Promise(function () {});
              var promise = original.apply(W, arguments);
              return Promise.resolve(promise).then(
                function (value) { settled(); return value; },
                function (error) { settled(); throw error; });
            };
          });
        })
        """#)
        _ = installer?.call(withArguments: [ModuleScriptValues.function(began, in: context),
                                             ModuleScriptValues.function(settled, in: context), webAssemblyAsyncCalls])
    }

    private static func installDone(_ context: JSContext, _ session: ModuleScriptSession) {
        let done: @convention(block) () -> Void = { [weak session] in
            live(session)?.done((JSContext.currentArguments() as? [JSValue])?.first)
        }
        context.setObject(done, forKeyedSubscript: "$done" as NSString)
    }

     

     
    private static func installMessage(_ context: JSContext, _ session: ModuleScriptSession) {
        guard let message = session.request else { return }
        if session.declaration.family == .quantumultX {
            return ModuleScriptQuantumultX.installMessage(message, in: context, for: session)
        }
        let request = JSValue(newObjectIn: context)!
        request.setObject(message.url, forKeyedSubscript: "url" as NSString)
        request.setObject(message.method, forKeyedSubscript: "method" as NSString)
        request.setObject(message.id, forKeyedSubscript: "id" as NSString)
        request.setObject(headersObject(message.headers, in: context), forKeyedSubscript: "headers" as NSString)
        if session.phase == .request, let body = exposedBody(session, in: context) {
            request.setObject(body, forKeyedSubscript: "body" as NSString)
        }
        context.setObject(request, forKeyedSubscript: "$request" as NSString)

        guard session.phase == .response, let response = session.response else { return }
        let object = JSValue(newObjectIn: context)!
        object.setObject(response.status, forKeyedSubscript: "status" as NSString)
        object.setObject(headersObject(response.headers, in: context), forKeyedSubscript: "headers" as NSString)
        if let body = exposedBody(session, in: context) {
            object.setObject(body, forKeyedSubscript: "body" as NSString)
        }
        context.setObject(object, forKeyedSubscript: "$response" as NSString)
    }

     
    static func headersObject(_ headers: [ModuleScriptHeader], in context: JSContext) -> JSValue {
        let object = JSValue(newObjectIn: context)!
        for header in ModuleScriptHeaderFolding.fold(headers) {
            object.setObject(header.value, forKeyedSubscript: header.name as NSString)
        }
        return object
    }

     
     
     
     
     
     
     
    private static func exposedBody(_ session: ModuleScriptSession, in context: JSContext) -> Any? {
        guard session.declaration.requiresBody, let body = session.body else { return nil }
        guard !body.isEmpty || session.declaration.family == .loon else { return nil }
        if session.declaration.binaryBodyMode { return ModuleScriptValues.uint8Array(body, in: context) }
        return String(decoding: body, as: UTF8.self)
    }

     

    private static func installIdentity(_ context: JSContext, _ session: ModuleScriptSession) {
         
        if session.declaration.family != .quantumultX {
            let script = JSValue(newObjectIn: context)!
            script.setObject(session.declaration.name, forKeyedSubscript: "name" as NSString)
            script.setObject(session.declaration.kind.scriptType(in: session.declaration.family),
                             forKeyedSubscript: "type" as NSString)
            script.setObject(ModuleScriptIdentity.startTime(session.startedAt, family: session.declaration.family),
                             forKeyedSubscript: "startTime" as NSString)
            script.setObject(session.sessionID, forKeyedSubscript: "sessionID" as NSString)
            script.setObject(session.declaration.binaryBodyMode, forKeyedSubscript: "binaryBodyMode" as NSString)
            context.setObject(script, forKeyedSubscript: "$script" as NSString)
        }
         
        if let argument = session.declaration.argument, let value = argumentValue(argument, in: context) {
            context.setObject(value, forKeyedSubscript: "$argument" as NSString)
        }
         
        if let trigger = session.declaration.trigger {
            context.setObject(trigger, forKeyedSubscript: "$trigger" as NSString)
        }
         
         
         
         
        ModuleScriptIdentity.install(into: context, family: session.declaration.family, kind: session.declaration.kind,
                                     environment: session.services.environment, scriptPath: session.declaration.scriptPath)
         
         
         
        if let parameters = session.declaration.environmentParameters,
           let object = try? JSONSerialization.jsonObject(with: Data(parameters.utf8)) as? [String: Any],
           let environment = context.objectForKeyedSubscript("$environment"), environment.isObject {
            environment.setObject(object, forKeyedSubscript: "params" as NSString)
        }
    }

     
     
     
     
     
    private static func argumentValue(_ argument: ModuleScriptArgument, in context: JSContext) -> JSValue? {
        switch argument {
        case .text(let text):
            return JSValue(object: text, in: context)
        case .object(let fields):
            guard let object = JSValue(newObjectIn: context) else { return nil }
            for field in fields {
                let value: JSValue?
                switch field.value {
                case .string(let text): value = JSValue(object: text, in: context)
                case .number(let number): value = JSValue(double: number, in: context)
                case .bool(let flag): value = JSValue(bool: flag, in: context)
                case .null: value = JSValue(nullIn: context)
                }
                object.setObject(value, forKeyedSubscript: field.name as NSString)
            }
            return object
        }
    }

     

    private static func installStore(_ context: JSContext, _ session: ModuleScriptSession) {
         
         
        let owner = ModuleScriptStore.Owner(session.declaration)
        let read: @convention(block) (JSValue) -> Any = { [weak session] key in
            guard let session = live(session) else { return NSNull() }
            let name = ModuleScriptValues.isAbsent(key) ? nil : key.toString()
            return session.store.read(key: name, by: owner) ?? NSNull()
        }
         
         
        let write: @convention(block) (JSValue, JSValue) -> Bool = { [weak session] value, key in
            guard let session = live(session) else { return false }
            let text = ModuleScriptValues.isAbsent(value) ? nil : value.toString()
            let name = ModuleScriptValues.isAbsent(key) ? nil : key.toString()
            return session.store.write(text, key: name, by: owner)
        }
         
        let remove: @convention(block) () -> Bool = { [weak session] in
            live(session)?.store.remove() ?? false
        }
        let store = JSValue(newObjectIn: context)!
        store.setObject(read, forKeyedSubscript: "read" as NSString)
        store.setObject(write, forKeyedSubscript: "write" as NSString)
        store.setObject(remove, forKeyedSubscript: "remove" as NSString)
        context.setObject(store, forKeyedSubscript: "$persistentStore" as NSString)
    }

     

    private static func installUtils(_ context: JSContext, _ session: ModuleScriptSession) {
        let ungzip: @convention(block) (JSValue) -> Any = { [weak session] input in
            guard let session = live(session), let context = JSContext.current() else { return NSNull() }
            guard let data = ModuleScriptValues.bytes(input, textAllowed: false) else {
                session.log(#"$utils.ungzip: the argument is not a Uint8Array; null"#)
                return NSNull()
            }
            switch ModuleScriptGzip.ungzip(data, limit: session.limits.decompressedBytesNow ?? .max) {
            case .success(let output):
                return ModuleScriptValues.uint8Array(output, in: context) ?? NSNull()
            case .failure(let failure):
                session.log(#"$utils.ungzip: \#(failure); null"#)
                return NSNull()
            }
        }
        let geoip: @convention(block) (JSValue) -> Any = { [weak session] ip in
            guard let session = live(session), let address = ModuleScriptValues.string(ip) else { return NSNull() }
            return session.services.geoip(address) ?? NSNull()
        }
        let ipasn: @convention(block) (JSValue) -> Any = { [weak session] _ in
            live(session)?.log(#"$utils.ipasn: the tunnel has no address-to-network database to ask; null"#)
            return NSNull()
        }
        let ipaso: @convention(block) (JSValue) -> Any = { [weak session] _ in
            live(session)?.log(#"$utils.ipaso: the tunnel has no address-to-network database to ask; null"#)
            return NSNull()
        }
        let utils = JSValue(newObjectIn: context)!
        utils.setObject(ungzip, forKeyedSubscript: "ungzip" as NSString)
        utils.setObject(geoip, forKeyedSubscript: "geoip" as NSString)
        utils.setObject(ipasn, forKeyedSubscript: "ipasn" as NSString)
        utils.setObject(ipaso, forKeyedSubscript: "ipaso" as NSString)
        context.setObject(utils, forKeyedSubscript: "$utils" as NSString)
    }

     

     
    static let httpClientMethods = ["get", "post", "put", "delete", "head", "options", "patch"]

     
     
    private static func installHTTPClient(_ context: JSContext, _ session: ModuleScriptSession) {
        let client = JSValue(newObjectIn: context)!
        for method in httpClientMethods {
            let call: @convention(block) (JSValue, JSValue) -> Void = { [weak session] options, callback in
                guard let session = live(session) else { return }
                let request = httpRequest(method: method.uppercased(), from: options, family: session.declaration.family)
                session.send(request, callback: ModuleScriptValues.isFunction(callback) ? callback : nil)
            }
            client.setObject(call, forKeyedSubscript: method as NSString)
        }
        context.setObject(client, forKeyedSubscript: "$httpClient" as NSString)
    }

     
     
     
     
    static func httpRequest(method: String, from options: JSValue, family: ModuleScriptFamily) -> ModuleScriptHTTPRequest {
        if options.isString { return ModuleScriptHTTPRequest(method: method, url: options.toString() ?? "") }
        guard options.isObject else { return ModuleScriptHTTPRequest(method: method, url: "") }
        var request = ModuleScriptHTTPRequest(
            method: method, url: ModuleScriptValues.string(options.objectForKeyedSubscript("url")) ?? "")
        let taken: Set<String> = ["url", "headers", "body", "timeout", "binary-mode"]
        if let headers = options.objectForKeyedSubscript("headers"), headers.isObject, !headers.isArray {
            for name in ModuleScriptValues.propertyNames(of: headers) {
                guard let field = headers.objectForKeyedSubscript(name), !ModuleScriptValues.isAbsent(field) else { continue }
                if field.isArray {
                    for item in field.toArray() ?? [] { request.headers.append(ModuleScriptHeader(name: name, value: "\(item)")) }
                } else {
                    request.headers.append(ModuleScriptHeader(name: name, value: field.toString() ?? ""))
                }
            }
        }
        if let body = options.objectForKeyedSubscript("body"), !ModuleScriptValues.isAbsent(body) {
             
             
            request.body = ModuleScriptValues.bytes(body, textAllowed: true)
                ?? Data(ModuleScriptValues.describe(body).utf8)
        }
        if let timeout = options.objectForKeyedSubscript("timeout"), timeout.isNumber {
            let value = timeout.toDouble()
            if value.isFinite, value > 0 { request.timeoutSeconds = family == .loon ? value / 1000 : value }
        }
        if let binary = options.objectForKeyedSubscript("binary-mode"), !ModuleScriptValues.isAbsent(binary) {
            request.binaryMode = binary.toBool()
        }
        for name in ModuleScriptValues.propertyNames(of: options) where !taken.contains(name) {
            guard let value = options.objectForKeyedSubscript(name), !ModuleScriptValues.isAbsent(value) else { continue }
            request.options[name] = ModuleScriptValues.describe(value)
        }
        return request
    }

     

    private static func installNotification(_ context: JSContext, _ session: ModuleScriptSession) {
        let post: @convention(block) () -> Void = { [weak session] in
            guard let session = live(session) else { return }
            let arguments = JSContext.currentArguments() as? [JSValue] ?? []
            _ = session.notify(ModuleScriptGlobals.notification(
                from: arguments, scriptName: session.declaration.name, log: session.log))
        }
         
        let object = JSValue(newObjectIn: context)!
        object.setObject(post, forKeyedSubscript: "post" as NSString)
        context.setObject(object, forKeyedSubscript: "$notification" as NSString)
    }

     
     
     
     
     
     
     
    static func notification(from arguments: [JSValue], scriptName: String, log: (String) -> Void) -> ModuleScriptNotificationRequest {
        func text(_ index: Int) -> String {
            guard index < arguments.count, !ModuleScriptValues.isAbsent(arguments[index]) else { return "" }
            return arguments[index].toString() ?? ""
        }
        var request = ModuleScriptNotificationRequest(
            scriptName: scriptName, title: text(0), subtitle: text(1), body: text(2),
            openURL: nil, clipboardText: nil, sound: false)
        if arguments.count > 4, arguments[4].isNumber {
            let milliseconds = arguments[4].toDouble()
            if milliseconds.isFinite, milliseconds > 0 { request.delaySeconds = milliseconds / 1000 }
        }
        guard arguments.count > 3, !ModuleScriptValues.isAbsent(arguments[3]) else { return request }
        let options = arguments[3]
        if options.isString {
            request.openURL = options.toString()
            return request
        }
        guard options.isObject else { return request }
        func first(_ keys: [String]) -> String? {
            keys.lazy.compactMap { ModuleScriptValues.string(options.objectForKeyedSubscript($0)) }.first
        }
        request.openURL = first(["url", "open-url", "openUrl"])
        request.mediaURL = first(["media-url", "mediaUrl"])
        if ModuleScriptValues.string(options.objectForKeyedSubscript("action")) == "clipboard" {
            request.clipboardText = first(["text"])
        }
        request.clipboardText = request.clipboardText ?? first(["update-pasteboard", "clipboard"])
        if let sound = options.objectForKeyedSubscript("sound"), !ModuleScriptValues.isAbsent(sound) {
            request.sound = sound.toBool()
        }
        if !ModuleScriptValues.isAbsent(options.objectForKeyedSubscript("media-base64")) {
            log(#"$notification.post: media-base64 not attached (the record carries a picture's address, not the picture)"#)
        }
        return request
    }

     

     
     
    static let maximumSubPolicies = 4096

     
     
     
     
     
    private static func installConfig(_ context: JSContext, _ session: ModuleScriptSession) {
        guard session.declaration.family == .loon else { return }
        let access = session.services.config
        let config = JSValue(newObjectIn: context)!
        let nothing = #"no running configuration to read here"#
        let getConfig: @convention(block) () -> String = { [weak session] in
            guard let session = live(session) else { return "{}" }
            guard access.isAvailable() else {
                session.log(#"$config.getConfig: \#(nothing); {}"#)
                return "{}"
            }
             
             
            var object: [String: Any] = ["all_policy_groups": access.groups(), "all_buildin_nodes": access.builtins()]
            if let mode = access.mode(), let model = ["direct": 0, "rule": 1, "global": 2][mode] { object["running_model"] = model }
            if let global = access.selected("GLOBAL") { object["global_proxy"] = global }
            if let final = access.final() { object["final"] = final }
            guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
            return String(decoding: data, as: UTF8.self)
        }
        let subPolicies: @convention(block) (JSValue, JSValue) -> Void = { [weak session] group, callback in
            guard let session = live(session) else { return }
            var text = ""
            if !access.isAvailable() {
                session.log(#"$config.getSubPolicies: \#(nothing); """#)
            } else if let name = ModuleScriptValues.string(group), let members = access.members(name, maximumSubPolicies) {
                if members.count == maximumSubPolicies {
                    session.log(#"$config.getSubPolicies(\#(name)): the first \#(maximumSubPolicies) members only"#)
                }
                let list = members.map { ["name": $0.name, "type": $0.kind] }
                if let data = try? JSONSerialization.data(withJSONObject: list, options: [.sortedKeys]) {
                    text = String(decoding: data, as: UTF8.self)
                }
            }
             
            _ = session.addTimer(callback, milliseconds: 0, arguments: [text])
        }
        let selected: @convention(block) (JSValue) -> Any = { [weak session] group in
            guard let session = live(session) else { return NSNull() }
            guard access.isAvailable() else {
                session.log(#"$config.getSelectedPolicy: \#(nothing); null"#)
                return NSNull()
            }
            guard let name = ModuleScriptValues.string(group) else { return NSNull() }
            return access.selected(name) ?? NSNull()
        }
        let select: @convention(block) (JSValue, JSValue) -> Bool = { [weak session] groups, policies in
            guard let session = live(session) else { return false }
            var pairs: [(String, String)] = []
            if let group = ModuleScriptValues.string(groups), let policy = ModuleScriptValues.string(policies) {
                pairs = [(group, policy)]
            } else if groups.isArray, policies.isArray {
                let names = (groups.toArray() ?? []).compactMap { $0 as? String }
                let choices = (policies.toArray() ?? []).compactMap { $0 as? String }
                guard !names.isEmpty, names.count == choices.count,
                      names.count == (groups.toArray() ?? []).count, choices.count == (policies.toArray() ?? []).count else {
                    session.log(#"$config.setSelectPolicy: two lists of names of the same length, or two names; false"#)
                    return false
                }
                pairs = Array(zip(names, choices))
            } else {
                session.log(#"$config.setSelectPolicy: two lists of names of the same length, or two names; false"#)
                return false
            }
            var all = true
            for (group, policy) in pairs {
                let taken = session.services.selectPolicy(group, policy)
                session.log(#"$config.setSelectPolicy(\#(group), \#(policy)) -> \#(taken)"#)
                all = all && taken
            }
            return all
        }
        let setRunningModel: @convention(block) (JSValue) -> Bool = { [weak session] model in
            guard let session = live(session) else { return false }
            guard access.isAvailable() else {
                session.log(#"$config.setRunningModel: \#(nothing); false"#)
                return false
            }
             
            guard let number = ModuleScriptValues.integer(model), let mode = [0: "direct", 1: "rule", 2: "global"][number] else {
                session.log(#"$config.setRunningModel: 0, 1 or 2; false"#)
                return false
            }
            if mode == #"global"#, let refusal = access.globalRefusal() {
                session.log(#"$config.setRunningModel(\#(number)): \#(refusal); false"#)
                return false
            }
            let changed = access.setMode(mode)
            session.log(#"$config.setRunningModel(\#(number)) -> \#(changed)"#)
            return changed
        }
        config.setObject(getConfig, forKeyedSubscript: "getConfig" as NSString)
        config.setObject(select, forKeyedSubscript: "setSelectPolicy" as NSString)
        config.setObject(subPolicies, forKeyedSubscript: "getSubPolicies" as NSString)
        config.setObject(subPolicies, forKeyedSubscript: "getSubPolicys" as NSString)
        config.setObject(selected, forKeyedSubscript: "getSelectedPolicy" as NSString)
        config.setObject(selected, forKeyedSubscript: "getPolicy" as NSString)
        config.setObject(setRunningModel, forKeyedSubscript: "setRunningModel" as NSString)
        context.setObject(config, forKeyedSubscript: "$config" as NSString)
    }

     

    static let dnsProtocols: Set<String> = ["auto", "udp", "doh", "doh3", "quic"]

     
     
     
    private static func installDNS(_ context: JSContext, _ session: ModuleScriptSession) {
        guard session.declaration.family == .loon else { return }
        let dns = JSValue(newObjectIn: context)!
        let query: @convention(block) (JSValue, JSValue) -> Void = { [weak session] options, callback in
            guard let session = live(session) else { return }
            session.queryDNS(dnsQuery(options), callback: ModuleScriptValues.isFunction(callback) ? callback : nil)
        }
        dns.setObject(query, forKeyedSubscript: "query" as NSString)
        context.setObject(dns, forKeyedSubscript: "$dns" as NSString)
    }

     
     
     
     
     
    static func dnsQuery(_ options: JSValue) -> Result<ModuleScriptDNSQuery, ModuleScriptDNSFailure> {
        func refused(_ code: String, _ message: String) -> Result<ModuleScriptDNSQuery, ModuleScriptDNSFailure> {
            .failure(ModuleScriptDNSFailure(code: code, message: message))
        }
        guard options.isObject, !options.isArray else { return refused("INVALID_ARGUMENT", #"options is an object with a domain"#) }
        let domainValue = options.forProperty("domain")
        guard let domainValue, domainValue.isString, let domain = domainValue.toString(),
              !domain.trimmingCharacters(in: .whitespaces).isEmpty else {
            return refused("INVALID_ARGUMENT", #"options.domain is required"#)
        }
        var protocolName: String?
        if let value = options.forProperty("protocol"), !ModuleScriptValues.isAbsent(value) {
            guard value.isString, let name = value.toString()?.lowercased(), dnsProtocols.contains(name) else {
                return refused("UNSUPPORTED_PROTOCOL", #"options.protocol is auto, udp, doh, doh3 or quic"#)
            }
            protocolName = name
        }
        var server: String?
        if let value = options.forProperty("server"), !ModuleScriptValues.isAbsent(value) {
            guard value.isString, let text = value.toString(), !text.isEmpty else {
                return refused("INVALID_SERVER", #"options.server is a server's address"#)
            }
            server = text
        }
        if let protocolName, protocolName != "auto", server == nil {
            return refused("INVALID_ARGUMENT", #"a \#(protocolName) query needs options.server"#)
        }
        var timeout = 3000
        if let value = options.forProperty("timeout"), !ModuleScriptValues.isAbsent(value) {
            let number = value.isNumber ? value.toDouble() : .nan
            guard number.isFinite, number > 0 else { return refused("INVALID_ARGUMENT", #"options.timeout is milliseconds above 0"#) }
            timeout = max(1, min(Int(number), 30_000))
        }
        return .success(ModuleScriptDNSQuery(domain: domain, protocolName: protocolName, server: server, timeoutMilliseconds: timeout))
    }

     

    static let surgeStubs = ["selectGroupDetails", "setOutboundMode", "setHTTPCaptureEnabled", "setRewriteEnabled",
                             "setEnhancedModeEnabled", "setCellularModeEnabled"]

    private static func installSurge(_ context: JSContext, _ session: ModuleScriptSession) {
         
         
        guard session.declaration.family != .loon else { return }
        let surge = JSValue(newObjectIn: context)!
        let select: @convention(block) (JSValue, JSValue) -> Bool = { [weak session] group, policy in
            guard let session = live(session), let group = ModuleScriptValues.string(group),
                  let policy = ModuleScriptValues.string(policy) else { return false }
            let selected = session.services.selectPolicy(group, policy)
            session.log(#"$surge.setSelectGroupPolicy(\#(group), \#(policy)) -> \#(selected)"#)
            return selected
        }
        surge.setObject(select, forKeyedSubscript: "setSelectGroupPolicy" as NSString)
        let logbook: @convention(block) (JSValue) -> Bool = { [weak session] content in
            guard let session = live(session) else { return false }
            session.log(#"[logbook] \#(ModuleScriptValues.describe(content))"#)
            return true
        }
        surge.setObject(logbook, forKeyedSubscript: "logbook" as NSString)
        let retest: @convention(block) (JSValue, JSValue) -> Bool = { [weak session] group, callback in
            guard let session = live(session) else { return false }
            session.log(#"$surge.retestGroup(\#(group.toString() ?? "")) is not available in Clash; nothing changed"#)
            if ModuleScriptValues.isFunction(callback) {
                _ = session.addTimer(callback, milliseconds: 0,
                                     arguments: [["error": #"$surge.retestGroup is not available in Clash"#]])
            }
            return false
        }
        surge.setObject(retest, forKeyedSubscript: "retestGroup" as NSString)
        for name in surgeStubs {
            let stub: @convention(block) () -> Any = { [weak session] in
                live(session)?.log(#"$surge.\#(name) is not available in Clash; nothing changed"#)
                if name == "selectGroupDetails" { return NSNull() }
                return false
            }
            surge.setObject(stub, forKeyedSubscript: name as NSString)
        }
        context.setObject(surge, forKeyedSubscript: "$surge" as NSString)
    }
}
#endif
