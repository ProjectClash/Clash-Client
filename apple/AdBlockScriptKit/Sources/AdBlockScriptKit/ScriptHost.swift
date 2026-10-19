import Foundation

/// One request from JavaScript to the host.
///
/// The prelude turns every platform API into one of these. Keeping a single
/// primitive means the native surface is small enough to audit, and a platform
/// API that is missing on a host fails in one place instead of five.
public struct ScriptHostCall: Sendable {
    /// The primitive's name, e.g. `http`, `store.read`, `notify`, `dns.query`.
    public var name: String
    /// The JSON object the prelude built, as UTF-8 bytes.
    public var payload: Data

    public init(name: String, payload: Data) {
        self.name = name
        self.payload = payload
    }
}

/// What the host answers. `value` is JSON the prelude parses.
public struct ScriptHostAnswer: Sendable {
    public var value: Data
    public var error: String?

    public init(value: Data = Data("null".utf8), error: String? = nil) {
        self.value = value
        self.error = error
    }

    public static func json(_ object: [String: Any]) -> ScriptHostAnswer {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            return ScriptHostAnswer(error: "the host could not encode its answer")
        }
        return ScriptHostAnswer(value: data)
    }

    public static func failure(_ message: String) -> ScriptHostAnswer {
        ScriptHostAnswer(error: message)
    }
}

/// A notification a script asked for.
public struct ScriptNotification: Equatable, Sendable {
    public var title: String
    public var subtitle: String
    public var body: String
    public var openURL: String?
    public var mediaURL: String?
    public var clipboard: String?
    public var autoDismiss: Bool?
    public var sound: Bool?

    public init(title: String, subtitle: String = "", body: String = "",
                openURL: String? = nil, mediaURL: String? = nil, clipboard: String? = nil,
                autoDismiss: Bool? = nil, sound: Bool? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.openURL = openURL
        self.mediaURL = mediaURL
        self.clipboard = clipboard
        self.autoDismiss = autoDismiss
        self.sound = sound
    }
}

/// Everything a run needs from the outside world.
///
/// The tunnel implements this with its own connector (so script HTTP goes
/// through the same policy the app's traffic does), the app group's storage and
/// the system notification centre. Tests implement it with a dictionary and a
/// canned HTTP responder.
public protocol ScriptHostServices: AnyObject, Sendable {
    /// A request the script made. Called on the run's queue; answer on the same
    /// queue is not required.
    func perform(_ call: ScriptHostCall, completion: @escaping @Sendable (ScriptHostAnswer) -> Void)
    /// A line the script logged.
    func log(_ line: String, level: String)
    /// A notification the script posted.
    func notify(_ notification: ScriptNotification)
}

/// The synchronous slice of the host services.
///
/// `$persistentStore.read`, `$prefs.valueForKey` and `$config.getConfig` are
/// synchronous on every platform — a script reads at the top of the file and
/// uses the value three lines later. Answering them needs a path that returns
/// on the calling thread, which is why it is a separate protocol from the
/// asynchronous `perform`.
public protocol ScriptSynchronousServices: AnyObject, Sendable {
    /// The JSON answer for a call that must be answered inline. `null` when the
    /// call has no synchronous answer.
    func synchronousAnswer(name: String, payload: Data) -> String
}
