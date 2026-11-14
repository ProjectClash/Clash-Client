import Foundation

 
 
 
 
 
 
 

 
 
public struct ClashFeedbackPresentation: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
         
         
        case loading
        case success
         
        case information
         
        case warning
         
        case error
    }

     
     
     
    public enum Action: String, Equatable, Sendable {
        case details
        case retry
        case undo
         
        case reveal
    }

    public struct Progress: Equatable, Sendable {
        public let completed: Int
        public let total: Int

        public init(completed: Int, total: Int) {
            self.completed = completed
            self.total = total
        }
    }

    public let kind: Kind
     
    public let title: ClashDisplayText
     
     
    public let message: ClashDisplayText?
    public let accessibilityIdentifier: String
    public let progress: Progress?
    public let action: Action?
     
     
    public let isBatchSummary: Bool

    public init(
        kind: Kind,
        title: ClashDisplayText,
        message: ClashDisplayText? = nil,
        progress: Progress? = nil,
        action: Action? = nil,
        isBatchSummary: Bool = false,
        accessibilityIdentifier: String
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.progress = progress
        self.action = action
        self.isBatchSummary = isBatchSummary
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    public static func loading(
        title: ClashDisplayText,
        message: ClashDisplayText? = nil,
        progress: Progress? = nil,
        accessibilityIdentifier: String
    ) -> Self {
        Self(kind: .loading, title: title, message: message, progress: progress,
             accessibilityIdentifier: accessibilityIdentifier)
    }

    public static func success(
        title: ClashDisplayText,
        message: ClashDisplayText? = nil,
        action: Action? = nil,
        isBatchSummary: Bool = false,
        accessibilityIdentifier: String
    ) -> Self {
        Self(kind: .success, title: title, message: message, action: action,
             isBatchSummary: isBatchSummary, accessibilityIdentifier: accessibilityIdentifier)
    }

    public static func information(
        title: ClashDisplayText,
        message: ClashDisplayText? = nil,
        action: Action? = nil,
        isBatchSummary: Bool = false,
        accessibilityIdentifier: String
    ) -> Self {
        Self(kind: .information, title: title, message: message, action: action,
             isBatchSummary: isBatchSummary, accessibilityIdentifier: accessibilityIdentifier)
    }

    public static func warning(
        title: ClashDisplayText,
        message: ClashDisplayText? = nil,
        action: Action? = nil,
        isBatchSummary: Bool = false,
        accessibilityIdentifier: String
    ) -> Self {
        Self(kind: .warning, title: title, message: message, action: action,
             isBatchSummary: isBatchSummary, accessibilityIdentifier: accessibilityIdentifier)
    }

    public static func error(
        title: ClashDisplayText,
        message: ClashDisplayText? = nil,
        action: Action? = nil,
        isBatchSummary: Bool = false,
        accessibilityIdentifier: String
    ) -> Self {
        Self(kind: .error, title: title, message: message, action: action,
             isBatchSummary: isBatchSummary, accessibilityIdentifier: accessibilityIdentifier)
    }

     
     
     
    public var requiresExplicitDismissal: Bool {
        switch kind {
        case .loading, .success:
            return false
        case .information, .warning, .error:
            return true
        }
    }

     
     
     
     
}

 
 
 
public struct ClashFeedbackLifetime: Equatable, Sendable {
     
     
     
    public struct Reading: Equatable, Sendable {
        public var base: TimeInterval
        public var perCharacter: TimeInterval
        public var minimum: TimeInterval
        public var maximum: TimeInterval

        public init(base: TimeInterval, perCharacter: TimeInterval, minimum: TimeInterval, maximum: TimeInterval) {
            self.base = base
            self.perCharacter = perCharacter
            self.minimum = minimum
            self.maximum = maximum
        }

        public func seconds(characters: Int) -> TimeInterval {
            min(maximum, max(minimum, base + perCharacter * TimeInterval(max(0, characters))))
        }
    }

     
    public var reading: Reading
     
    public var undo: TimeInterval?
    public var warning: TimeInterval?
    public var error: TimeInterval?
     
    public var withAction: TimeInterval?
    public var batchSummary: TimeInterval?

    public init(
        reading: Reading,
        undo: TimeInterval?,
        warning: TimeInterval?,
        error: TimeInterval?,
        withAction: TimeInterval?,
        batchSummary: TimeInterval?
    ) {
        self.reading = reading
        self.undo = undo
        self.warning = warning
        self.error = error
        self.withAction = withAction
        self.batchSummary = batchSummary
    }

     
     
     
    public func seconds(for presentation: ClashFeedbackPresentation, characters: Int) -> TimeInterval? {
        if presentation.kind == .loading { return nil }
        if presentation.isBatchSummary { return batchSummary }
        switch presentation.action {
        case .undo?: return undo
        case .details?, .retry?, .reveal?: return withAction
        case nil: break
        }
        switch presentation.kind {
        case .loading: return nil
        case .success, .information: return reading.seconds(characters: characters)
        case .warning: return warning
        case .error: return error
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashFeedbackCenterState: Equatable, Sendable {
    public struct ShownResult: Equatable, Sendable {
        public let id: Int
        public fileprivate(set) var presentation: ClashFeedbackPresentation
         
         
         
        public fileprivate(set) var screen: String?
         
         
         
        public let operation: String?
         
        public fileprivate(set) var deadline: Date?
         
        fileprivate var remaining: TimeInterval?

        var isTimed: Bool { deadline != nil || remaining != nil }
        var waits: Bool { !isTimed && presentation.kind != .loading }
    }

    public private(set) var current: ShownResult?
     
    public private(set) var covered: ShownResult?
    private var nextID = 1
    private var pausedAt: Date?

    public init() {}

     
     
    @discardableResult
    public mutating func show(
        _ presentation: ClashFeedbackPresentation,
        screen: String?,
        operation: String? = nil,
        characters: Int = 0,
        now: Date,
        lifetime: ClashFeedbackLifetime
    ) -> Int {
        let id = nextID
        nextID += 1
        var entry = ShownResult(id: id, presentation: presentation, screen: screen, operation: operation,
                          deadline: nil, remaining: nil)
        schedule(&entry, seconds: lifetime.seconds(for: presentation, characters: characters), now: now)
        if entry.isTimed {
             
             
             
             
             
            if let showing = current, showing.waits || showing.presentation.kind == .loading,
               operation == nil || showing.operation != operation {
                covered = showing
            }
            if let operation, covered?.operation == operation { covered = nil }
        } else {
             
            covered = nil
        }
        current = entry
        return id
    }

     
     
     
    @discardableResult
    public mutating func update(
        _ id: Int,
        to presentation: ClashFeedbackPresentation,
        screen: String? = nil,
        characters: Int = 0,
        now: Date,
        lifetime: ClashFeedbackLifetime
    ) -> Bool {
        if var hidden = covered, hidden.id == id {
             
             
             
             
            hidden.presentation = presentation
            if let screen { hidden.screen = screen }
            hidden.deadline = nil
            hidden.remaining = lifetime.seconds(for: presentation, characters: characters)
            covered = hidden
            return true
        }
        guard var entry = current, entry.id == id else { return false }
        entry.presentation = presentation
        if let screen { entry.screen = screen }
        schedule(&entry, seconds: lifetime.seconds(for: presentation, characters: characters), now: now)
        current = entry
        return true
    }

     
    @discardableResult
    public mutating func expire(now: Date) -> Bool {
        guard let deadline = current?.deadline, deadline.timeIntervalSince(now) <= 0 else { return false }
        uncover(now: now)
        return true
    }

     
     
     
    public mutating func clear() {
        current = nil
        covered = nil
    }

     
     
    public mutating func dismiss(_ id: Int, now: Date = Date()) {
        if covered?.id == id {
            covered = nil
            return
        }
        guard current?.id == id else { return }
        uncover(now: now)
    }

     
     
    public mutating func leaveScreen(_ screen: String) {
        if let hidden = covered, hidden.screen == screen { covered = nil }
        guard let entry = current, entry.screen == screen, entry.waits else { return }
        current = nil
    }

     
     
    public mutating func pause(now: Date) {
        guard pausedAt == nil else { return }
        pausedAt = now
        if var entry = current, let deadline = entry.deadline {
            entry.remaining = max(0, deadline.timeIntervalSince(now))
            entry.deadline = nil
            current = entry
        }
    }

    public mutating func resume(now: Date) {
        guard pausedAt != nil else { return }
        pausedAt = nil
        if var entry = current, let remaining = entry.remaining {
            entry.deadline = now.addingTimeInterval(remaining)
            entry.remaining = nil
            current = entry
        }
    }

     
     
     
     
     
    public mutating func dropTransient(now: Date = Date()) {
        guard let entry = current, entry.isTimed, entry.presentation.action != .undo else { return }
        uncover(now: now)
    }

     
     
    private mutating func uncover(now: Date) {
        current = covered
        covered = nil
        if pausedAt == nil, var entry = current, let remaining = entry.remaining {
            entry.deadline = now.addingTimeInterval(remaining)
            entry.remaining = nil
            current = entry
        }
    }

    private func schedule(_ entry: inout ShownResult, seconds: TimeInterval?, now: Date) {
        guard let seconds else {
            entry.deadline = nil
            entry.remaining = nil
            return
        }
        if pausedAt != nil {
            entry.deadline = nil
            entry.remaining = seconds
        } else {
            entry.deadline = now.addingTimeInterval(seconds)
            entry.remaining = nil
        }
    }
}
