import Combine
import Foundation
import SwiftUI

 
 
public typealias ClashStoredSwitch<Key: Hashable> = ClashStoredValues<Key, Bool>

 
 
public struct ClashStoredWriteSaidElsewhere: Error, Equatable {
    public init() {}
}

 
 
 
 
 
 
@MainActor
public final class ClashWriteTurns {
    private var taken = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public init() {}

     
    public func run<T>(_ work: () async throws -> T) async rethrows -> T {
        if taken {
            await withCheckedContinuation { waiting.append($0) }
        }
        taken = true
        defer { handOn() }
        return try await work()
    }

    private func handOn() {
        if waiting.isEmpty {
            taken = false
        } else {
             
            waiting.removeFirst().resume()
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
public final class ClashStoredValues<Key: Hashable, Value: Equatable>: ObservableObject {
    public typealias Write = @MainActor (Value) async throws -> Void

     
    public enum ReadBack: Sendable {
         
        case withTheWrite
         
         
        case whenRead
    }

     
     
    public final class Cell: ObservableObject {
        public let objectWillChange = ObservableObjectPublisher()
    }

    private struct Press {
        var value: Value
        var number: Int
    }

    private struct Waiting {
        var value: Value
        var readBack: ReadBack
        var write: Write
    }

    private var pressed: [Key: Press] = [:]
    private var presses = 0
    private var order: [Key] = []
    private var waiting: [Key: Waiting] = [:]
    private var writing: (key: Key, value: Value)?
     
     
     
     
    private var readWhileWriting = false
     
    private var unread: [Key: Int] = [:]
    private var failures: [Key: String] = [:]
    private var cells: [Key: Cell] = [:]
    private var runner: Task<Void, Never>?
    private let readBackTimeout: TimeInterval
    private let turns: ClashWriteTurns?

     
     
     
    public init(readBackTimeout: TimeInterval = 2, turns: ClashWriteTurns? = nil) {
        self.readBackTimeout = readBackTimeout
        self.turns = turns
    }

     

     
    public func shown(_ key: Key, stored: Value) -> Value {
        pressed[key]?.value ?? stored
    }

     
    public func pressedValue(_ key: Key) -> Value? {
        pressed[key]?.value
    }

     
    public var pressedValues: [Key: Value] {
        pressed.mapValues(\.value)
    }

     
    public func isPending(_ key: Key) -> Bool {
        waiting[key] != nil || writing?.key == key || unread[key] != nil
    }

     
    public func isWriting(_ key: Key) -> Bool {
        writing?.key == key
    }

     
    public var hasPending: Bool {
        !waiting.isEmpty || writing != nil || !unread.isEmpty
    }

     
    public func failure(_ key: Key) -> String? {
        failures[key]
    }

     
     
    public func cell(_ key: Key) -> Cell {
        if let cell = cells[key] { return cell }
        let cell = Cell()
        cells[key] = cell
        return cell
    }

     

     
     
    public func binding(_ key: Key, stored: Value, readBack: ReadBack = .withTheWrite,
                        write: @escaping Write) -> Binding<Value> {
        Binding(get: { self.shown(key, stored: stored) },
                set: { self.press(key, $0, readBack: readBack, write: write) })
    }

     
    public func press(_ key: Key, _ value: Value, readBack: ReadBack = .withTheWrite, write: @escaping Write) {
        change(key) {
            presses &+= 1
            pressed[key] = Press(value: value, number: presses)
            unread[key] = nil
            if let writing, writing.key == key, writing.value == value {
                 
                waiting[key] = nil
                order.removeAll { $0 == key }
            } else {
                if waiting[key] == nil { order.append(key) }
                waiting[key] = Waiting(value: value, readBack: readBack, write: write)
            }
        }
        if runner == nil {
            runner = Task { @MainActor [weak self] in await self?.drain() }
        }
    }

     
     
     
    public func read(_ key: Key, stored: Value) {
        if let writing, writing.key == key {
            if writing.value == stored { readWhileWriting = true }
            return
        }
        guard unread[key] != nil, waiting[key] == nil else { return }
        change(key) { settle(key) }
    }

     
    public func waitForWrites() async {
        while let runner {
            await runner.value
        }
    }

     
     
    public var isDraining: Bool { runner != nil }

     

    private func drain() async {
        while !order.isEmpty {
             
             
             
             
             
             
            if let turns {
                await turns.run { await writeNext() }
            } else {
                await writeNext()
            }
        }
        runner = nil
    }

     
    private func writeNext() async {
        guard let key = order.first else { return }
        order.removeFirst()
        guard let next = waiting.removeValue(forKey: key) else { return }
        change(key) {
            writing = (key, next.value)
            readWhileWriting = false
        }
        var failed: Error?
        do {
            try await next.write(next.value)
        } catch {
            failed = error
        }
        change(key) {
            writing = nil
            if let failed {
                failures[key] = Self.words(failed)
                 
                if waiting[key] == nil { pressed[key] = nil }
            } else {
                failures[key] = nil
                if waiting[key] == nil, let press = pressed[key] {
                    switch next.readBack {
                    case .withTheWrite:
                        settle(key)
                    case .whenRead where readWhileWriting:
                        settle(key)
                    case .whenRead:
                        unread[key] = press.number
                        letGo(key, press: press.number)
                    }
                }
            }
            readWhileWriting = false
        }
    }

    private func settle(_ key: Key) {
        pressed[key] = nil
        unread[key] = nil
    }

     
    private func letGo(_ key: Key, press number: Int) {
        let delay = UInt64(max(0, readBackTimeout) * 1_000_000_000)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, self.unread[key] == number else { return }
            self.change(key) { self.settle(key) }
        }
    }

    private func change(_ key: Key, _ body: () -> Void) {
        objectWillChange.send()
        cells[key]?.objectWillChange.send()
        body()
    }

    private static func words(_ error: Error) -> String? {
        if error is ClashStoredWriteSaidElsewhere { return nil }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

 
 
 
 
public struct ClashStoredToggle<Key: Hashable, Label: View>: View {
    private let switches: ClashStoredSwitch<Key>
    @ObservedObject private var cell: ClashStoredSwitch<Key>.Cell
    private let key: Key
    private let stored: Bool
    private let identifier: String
    private let set: (Bool) -> Void
    private let label: Label

     
     
    public init(_ switches: ClashStoredSwitch<Key>, key: Key, stored: Bool, identifier: String,
                set: @escaping (Bool) -> Void, @ViewBuilder label: () -> Label) {
        self.switches = switches
        cell = switches.cell(key)
        self.key = key
        self.stored = stored
        self.identifier = identifier
        self.set = set
        self.label = label()
    }

     
    public init(_ switches: ClashStoredSwitch<Key>, key: Key, stored: Bool, identifier: String,
                readBack: ClashStoredSwitch<Key>.ReadBack = .withTheWrite,
                write: @escaping ClashStoredSwitch<Key>.Write, @ViewBuilder label: () -> Label) {
        let binding = switches.binding(key, stored: stored, readBack: readBack, write: write)
        self.init(switches, key: key, stored: stored, identifier: identifier, set: { binding.wrappedValue = $0 }, label: label)
    }

    public var body: some View {
        Toggle(isOn: Binding(get: { switches.shown(key, stored: stored) }, set: set)) {
            label
        }
        .accessibilityIdentifier(identifier)
    }
}

 
 
 
public struct ClashStoredFailure<Key: Hashable, Value: Equatable, Content: View>: View {
    private let values: ClashStoredValues<Key, Value>
    @ObservedObject private var cell: ClashStoredValues<Key, Value>.Cell
    private let key: Key
    private let content: (String) -> Content

    public init(_ values: ClashStoredValues<Key, Value>, key: Key, @ViewBuilder content: @escaping (String) -> Content) {
        self.values = values
        cell = values.cell(key)
        self.key = key
        self.content = content
    }

    public var body: some View {
        if !values.isPending(key), let failure = values.failure(key) {
            content(failure)
        }
    }
}
