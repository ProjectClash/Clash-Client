 
 
 
 
 
 
 
 
 
 
 
 
 

 
 
 
 
 
 
 
 
 
struct LockedValueBox<Value> {

    @usableFromInline
    internal let _storage: LockStorage<Value>

     
    @inlinable
    init(_ value: Value) {
        self._storage = .create(value: value)
    }

     
    @inlinable
    func withLockedValue<T>(_ mutate: (inout Value) throws -> T) rethrows -> T {
        try self._storage.withLockedValue(mutate)
    }

     
     
     
     
     
    var unsafe: Unsafe {
        Unsafe(_storage: self._storage)
    }

     
    struct Unsafe {
        @usableFromInline
        let _storage: LockStorage<Value>

         
        @inlinable
        func lock() {
            self._storage.lock()
        }

         
        @inlinable
        func unlock() {
            self._storage.unlock()
        }

         
         
         
         
        @inlinable
        func withValueAssumingLockIsAcquired<Result>(
            _ mutate: (_ value: inout Value) throws -> Result
        ) rethrows -> Result {
            try self._storage.withUnsafeMutablePointerToHeader { value in
                try mutate(&value.pointee)
            }
        }
    }
}

extension LockedValueBox: @unchecked Sendable where Value: Sendable {}
