import Foundation
#if os(Linux)
import CJavaScriptCore
#else
import JavaScriptCore
#endif

/// The real engine: one `JSGlobalContext` per run, through the JavaScriptCore C
/// API.
///
/// The C API rather than the Objective-C `JSContext` class for two reasons: on
/// Linux there is no Objective-C bridge to wrap, and the C API is the same
/// surface on every platform, so the engine that passes the tests here is the
/// engine that ships.
///
/// A context per run rather than one shared context, because rewrite scripts
/// declare top-level `const` and `let` freely, and two scripts that both say
/// `const API = ...` would collide in a shared context — the second would throw
/// before it ran. A context cannot outlive its run either, which is what keeps a
/// bad script from leaving state behind for the next request.
///
/// Thread confinement: the context is created on the script's own thread and is
/// only touched from it. Host answers arrive asynchronously and are handed back
/// through `resolve`, which the run schedules on that same thread.
public final class JSCEngine: JSEngine, @unchecked Sendable {
    private var context: JSGlobalContextRef!
    private var group: JSContextGroupRef!
    private let lock = NSLock()
    private var hooks: JSEngineHooks?
    private var aborted = false

    /// Set by `ScriptRun`; supplies the answers `$persistentStore`, `$prefs`
    /// and `$config` need on the calling thread.
    public weak var synchronousServices: ScriptSynchronousServices?

    public init() throws {
        guard let group = JSContextGroupCreate() else {
            throw JSEngineError("JavaScriptCore could not create a VM")
        }
        guard let context = JSGlobalContextCreateInGroup(group, nil) else {
            JSContextGroupRelease(group)
            throw JSEngineError("JavaScriptCore could not create a context")
        }
        self.group = group
        self.context = context
        EngineRegistry.register(self, for: context)
    }

    /// How many engines are alive right now.
    ///
    /// Exposed for the leak test: a run that finishes has to take its context
    /// with it, and a number that climbs across runs is a leak.
    public static var liveEngines: Int { EngineRegistry.liveCount }

    /// Stops the script if it is still executing after `seconds`.
    ///
    /// The runner abandons a slow run at its deadline, but abandoning is not
    /// stopping: a script in `while (true)` would keep its thread and its CPU
    /// until the process died. JavaScriptCore can terminate it — the same
    /// `JSContextGroupSetExecutionTimeLimit` the Objective-C `JSContext` uses —
    /// and with no callback it throws "JavaScript execution terminated" out of
    /// the evaluation, which the run reports as its timeout.
    ///
    /// The limit is per context group, so it is set on the engine that owns one
    /// and cleared when the run ends: a later run reusing this group would
    /// otherwise inherit a budget it did not ask for.
    public func setExecutionTimeLimit(_ seconds: TimeInterval) {
        guard seconds > 0 else { return }
        JSContextGroupSetExecutionTimeLimit(group, seconds, nil, nil)
    }

    public func clearExecutionTimeLimit() {
        JSContextGroupClearExecutionTimeLimit(group)
    }

    deinit {
        EngineRegistry.unregister(context)
        JSGlobalContextRelease(context)
        JSContextGroupRelease(group)
    }

    // MARK: - Native hooks

    public func install(_ hooks: JSEngineHooks) throws {
        self.hooks = hooks
        let global = JSContextGetGlobalObject(context)
        let callback: @convention(c) (JSContextRef?, JSObjectRef?, JSObjectRef?, Int,
                                      UnsafePointer<JSValueRef?>?,
                                      UnsafeMutablePointer<JSValueRef?>?) -> JSValueRef? = {
            context, _, _, argc, argv, exception in
            guard let context, let engine = EngineRegistry.engine(for: context) else { return nil }
            return engine.dispatch(argc: argc, argv: argv, exception: exception)
        }
        // One function object for all operations; the prelude binds the names it
        // documents (`__clash_call` and friends) to it at load time.
        let native = JSObjectMakeFunctionWithCallback(context, "__clashNative".js, callback)
        var thrown: JSValueRef?
        // Not `DontDelete`: the prelude removes the primitive from the global
        // object after binding it, so a script cannot call the host directly.
        JSObjectSetProperty(context, global, "__clashNative".js, native,
                            JSPropertyAttributes(0), &thrown)
    }

    /// Runs one native operation. The prelude passes the operation's name.
    private func dispatch(argc: Int, argv: UnsafePointer<JSValueRef?>?,
                          exception: UnsafeMutablePointer<JSValueRef?>?) -> JSValueRef? {
        guard argc >= 1 else { return JSValueMakeUndefined(context) }
        let operation = string(context, argv?[0])
        switch operation {
        case "call":
            let name = argc > 1 ? string(context, argv?[1]) : ""
            let payload = argc > 2 ? string(context, argv?[2]) : "null"
            let answer = synchronousServices?.synchronousAnswer(name: name, payload: Data(payload.utf8)) ?? "null"
            return answer.jsValue(context)
        case "host":
            let name = argc > 1 ? string(context, argv?[1]) : ""
            let payload = argc > 2 ? string(context, argv?[2]) : "null"
            let callback = argc > 3 ? Int(JSValueToNumber(context, argv?[3], exception)) : -1
            hooks?.hostCall(name, Data(payload.utf8), callback)
            return JSValueMakeUndefined(context)
        case "log":
            let message = argc > 1 ? string(context, argv?[1]) : ""
            let level = argc > 2 ? string(context, argv?[2]) : "info"
            hooks?.log(message, level)
            return JSValueMakeUndefined(context)
        case "timer":
            let delay = argc > 1 ? JSValueToNumber(context, argv?[1], exception) : 0
            let id = argc > 2 ? Int(JSValueToNumber(context, argv?[2], exception)) : 0
            hooks?.schedule(delay, id)
            return JSValueMakeUndefined(context)
        case "cancel":
            let id = argc > 1 ? Int(JSValueToNumber(context, argv?[1], exception)) : 0
            hooks?.cancelTimer(id)
            return JSValueMakeUndefined(context)
        case "now":
            return JSValueMakeNumber(context, hooks?.now() ?? 0)
        default:
            return JSValueMakeUndefined(context)
        }
    }

    // MARK: - Evaluation

    public func evaluate(_ script: String, sourceURL: String?) throws {
        guard let scriptRef = script.js else { throw JSEngineError("the script is not text") }
        defer { JSStringRelease(scriptRef) }
        let urlRef = sourceURL.flatMap { $0.js }
        defer { if let urlRef { JSStringRelease(urlRef) } }
        var thrown: JSValueRef?
        _ = JSEvaluateScript(context, scriptRef, nil, urlRef, 1, &thrown)
        if let thrown {
            let message = string(context, thrown)
            throw JSEngineError(message.isEmpty ? "the script threw" : message)
        }
    }

    /// Hands a host answer to the prelude. Called from the run's queue.
    public func resolve(callbackID: Int, answer: ScriptHostAnswer) {
        guard isUsable() else { return }
        let json = String(decoding: answer.value, as: UTF8.self)
        try? evaluate("__clashResolve(\(callbackID), \(json.jsLiteral), \(answer.error?.jsLiteral ?? "null"));",
                      sourceURL: nil)
    }

    public func fireTimer(_ id: Int) {
        guard isUsable() else { return }
        try? evaluate("__clashFireTimer(\(id));", sourceURL: nil)
    }

    public func setSynchronousServices(_ services: ScriptSynchronousServices?) {
        synchronousServices = services
    }

    public func isUsable() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !aborted
    }

    /// Marks the context as no longer worth talking to. A timed-out script may
    /// still be running; nothing is evaluated into its context afterwards, and
    /// the context is released when the run is deallocated.
    public func abandon() {
        lock.lock()
        aborted = true
        lock.unlock()
    }

    // MARK: - Value conversion

    private func string(_ context: JSContextRef, _ value: JSValueRef?) -> String {
        guard let value else { return "" }
        var exception: JSValueRef?
        guard let copy = JSValueToStringCopy(context, value, &exception) else { return "" }
        defer { JSStringRelease(copy) }
        let size = JSStringGetMaximumUTF8CStringSize(copy)
        var buffer = [CChar](repeating: 0, count: size)
        let written = JSStringGetUTF8CString(copy, &buffer, size)
        guard written > 1 else { return "" }
        return String(decoding: buffer.prefix(written - 1).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// Finds the engine that owns a context.
///
/// The JavaScriptCore C API hands a callback its context but no user data, so
/// the association has to live somewhere. A context is created per run and its
/// address is unique while it lives, which makes it a sound key; entries are
/// removed in `deinit`, and a collected engine answers `nil` instead of being
/// used.
private enum EngineRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var engines: [UnsafeRawPointer: Box] = [:]

    private final class Box {
        weak var value: JSCEngine?
        init(_ value: JSCEngine) { self.value = value }
    }

    static func register(_ engine: JSCEngine, for context: JSGlobalContextRef) {
        lock.lock()
        engines[UnsafeRawPointer(context)] = Box(engine)
        lock.unlock()
    }

    static func unregister(_ context: JSGlobalContextRef?) {
        guard let context else { return }
        lock.lock()
        engines.removeValue(forKey: UnsafeRawPointer(context))
        lock.unlock()
    }

    static func engine(for context: JSContextRef) -> JSCEngine? {
        lock.lock(); defer { lock.unlock() }
        return engines[UnsafeRawPointer(context)]?.value
    }

    /// How many contexts are still registered.
    ///
    /// A run that finishes must take its engine with it; a count that climbs
    /// across runs is a leak, and this is the only way to see one from a test.
    static var liveCount: Int {
        lock.lock(); defer { lock.unlock() }
        // A box whose engine has gone is a leftover registration, not a live
        // context, so the count is of the ones still holding an engine.
        return engines.values.filter { $0.value != nil }.count
    }
}

private extension String {
    /// A `JSStringRef` the caller releases.
    var js: JSStringRef? {
        withCString { JSStringCreateWithUTF8CString($0) }
    }

    /// This string as a JavaScript string literal, safe for any content.
    var jsLiteral: String {
        guard let data = try? JSONSerialization.data(withJSONObject: [self]) else { return "null" }
        let wrapped = String(decoding: data, as: UTF8.self)
        return String(wrapped.dropFirst().dropLast())
    }

    /// This string as a JavaScript value.
    func jsValue(_ context: JSContextRef) -> JSValueRef? {
        guard let ref = js else { return JSValueMakeNull(context) }
        defer { JSStringRelease(ref) }
        return JSValueMakeString(context, ref)
    }
}
