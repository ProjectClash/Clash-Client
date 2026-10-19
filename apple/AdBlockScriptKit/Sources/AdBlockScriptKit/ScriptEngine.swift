import Foundation

/// The JavaScript engine a run executes in.
///
/// Narrow on purpose: the runner gives the engine four native hooks and calls
/// back into it to hand over host answers and fire timers. `JSCEngine` is the
/// real one; tests can supply a stub to exercise the runner's bookkeeping
/// without a JavaScript engine at all.
public protocol JSEngine: AnyObject, Sendable {
    /// Installs the native hooks. Called once, before `evaluate`.
    func install(_ hooks: JSEngineHooks) throws
    /// Evaluates a script, throwing if it raised while evaluating.
    func evaluate(_ script: String, sourceURL: String?) throws
    /// Hands a host answer to the prelude's pending callback.
    func resolve(callbackID: Int, answer: ScriptHostAnswer)
    /// Runs a timer the script scheduled.
    func fireTimer(_ id: Int)
    /// Whether the context is still usable after a timeout was abandoned.
    func isUsable() -> Bool
    /// Gives the engine the answers storage and config need on the script
    /// thread. Optional: an engine without it answers `null` to those calls.
    func setSynchronousServices(_ services: ScriptSynchronousServices?)
    /// Marks a context that outlived its budget as no longer worth talking to.
    func abandon()
    /// Stops a script that is still executing after `seconds`.
    ///
    /// Distinct from `abandon`: that one stops listening, this one stops the
    /// script. An engine that cannot interrupt leaves the default, which only
    /// silences the run — the behaviour before this existed.
    func setExecutionTimeLimit(_ seconds: TimeInterval)
}

public extension JSEngine {
    func setSynchronousServices(_ services: ScriptSynchronousServices?) {}
    func abandon() {}
    func setExecutionTimeLimit(_ seconds: TimeInterval) {}
}

/// The four things JavaScript can do to the host.
public struct JSEngineHooks {
    /// The script called an API that needs the host. `callbackID` is `-1` for
    /// calls with no answer (logging, notifications, `$done`).
    public var hostCall: @Sendable (String, Data, Int) -> Void
    /// The script wrote to `console` or a platform log.
    public var log: @Sendable (String, String) -> Void
    /// The script asked for a timer, in milliseconds.
    public var schedule: @Sendable (Double, Int) -> Void
    /// The script cancelled a timer.
    public var cancelTimer: @Sendable (Int) -> Void
    /// Milliseconds since the run started.
    public var now: @Sendable () -> Double

    public init(hostCall: @escaping @Sendable (String, Data, Int) -> Void,
                log: @escaping @Sendable (String, String) -> Void,
                schedule: @escaping @Sendable (Double, Int) -> Void,
                cancelTimer: @escaping @Sendable (Int) -> Void,
                now: @escaping @Sendable () -> Double) {
        self.hostCall = hostCall
        self.log = log
        self.schedule = schedule
        self.cancelTimer = cancelTimer
        self.now = now
    }
}

/// The engine could not be prepared.
public struct JSEngineError: Error, Equatable, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
}
