#if os(iOS) || os(macOS)
import Foundation
import JavaScriptCore

 
 
enum ModuleScriptValues {
    static func isAbsent(_ value: JSValue?) -> Bool {
        guard let value else { return true }
        return value.isUndefined || value.isNull
    }

     
    static func string(_ value: JSValue?) -> String? {
        guard let value, !isAbsent(value), value.isString || value.isNumber else { return nil }
        return value.toString()
    }

    static func integer(_ value: JSValue?) -> Int? {
        guard let value, !isAbsent(value) else { return nil }
        if value.isNumber {
            let number = value.toDouble()
            return number.isFinite ? Int(number) : nil
        }
        if value.isString { return Int((value.toString() ?? "").trimmingCharacters(in: .whitespaces)) }
        return nil
    }

     
     
     
     
     
     
     
     
    static func function(_ block: Any, in context: JSContext) -> JSValue {
        JSValue(object: block, in: context)
    }

    static func isFunction(_ value: JSValue?) -> Bool {
        guard let value, value.isObject, let context = value.context,
              let object = JSValueToObject(context.jsGlobalContextRef, value.jsValueRef, nil) else { return false }
        return JSObjectIsFunction(context.jsGlobalContextRef, object)
    }

     
    static func propertyNames(of value: JSValue) -> [String] {
        guard value.isObject, let context = value.context,
              let object = JSValueToObject(context.jsGlobalContextRef, value.jsValueRef, nil) else { return [] }
        let names = JSObjectCopyPropertyNames(context.jsGlobalContextRef, object)
        defer { JSPropertyNameArrayRelease(names) }
        return (0..<JSPropertyNameArrayGetCount(names)).map {
            JSStringCopyCFString(kCFAllocatorDefault, JSPropertyNameArrayGetNameAtIndex(names, $0)) as String
        }
    }

     
     
    static func bytes(_ value: JSValue, textAllowed: Bool) -> Data? {
        if value.isString { return textAllowed ? Data((value.toString() ?? "").utf8) : nil }
        guard value.isObject, let context = value.context else { return nil }
        let ctx = context.jsGlobalContextRef
        var exception: JSValueRef?
        let type = JSValueGetTypedArrayType(ctx, value.jsValueRef, &exception)
        guard exception == nil, type != kJSTypedArrayTypeNone,
              let object = JSValueToObject(ctx, value.jsValueRef, &exception), exception == nil else { return nil }
        if type == kJSTypedArrayTypeArrayBuffer {
            let length = JSObjectGetArrayBufferByteLength(ctx, object, &exception)
            guard exception == nil else { return nil }
            guard length > 0 else { return Data() }
            guard let base = JSObjectGetArrayBufferBytesPtr(ctx, object, &exception) else { return nil }
            return Data(bytes: base, count: length)
        }
        let length = JSObjectGetTypedArrayByteLength(ctx, object, &exception)
        guard exception == nil else { return nil }
        guard length > 0 else { return Data() }
         
         
        let offset = JSObjectGetTypedArrayByteOffset(ctx, object, &exception)
        guard exception == nil, let base = JSObjectGetTypedArrayBytesPtr(ctx, object, &exception) else { return nil }
        return Data(bytes: base.advanced(by: offset), count: length)
    }

    static func uint8Array(_ data: Data, in context: JSContext) -> JSValue? {
        let ctx = context.jsGlobalContextRef
        var exception: JSValueRef?
        guard let object = JSObjectMakeTypedArray(ctx, kJSTypedArrayTypeUint8Array, data.count, &exception),
              exception == nil else { return nil }
        if !data.isEmpty {
            let offset = JSObjectGetTypedArrayByteOffset(ctx, object, nil)
            guard let base = JSObjectGetTypedArrayBytesPtr(ctx, object, &exception) else { return nil }
            data.copyBytes(to: base.advanced(by: offset).assumingMemoryBound(to: UInt8.self), count: data.count)
        }
        return JSValue(jsValueRef: object, in: context)
    }

     
     
     
    static func describe(_ value: JSValue) -> String {
        if value.isString { return value.toString() ?? "" }
        if value.isObject, !isFunction(value), let context = value.context,
           !value.isInstance(of: context.objectForKeyedSubscript("Error")) {
             
            let handler = context.exceptionHandler
            context.exceptionHandler = { _, _ in }
            let json = context.objectForKeyedSubscript("JSON")?.invokeMethod("stringify", withArguments: [value])
            context.exceptionHandler = handler
            if let json, json.isString { return json.toString() ?? "" }
        }
        return value.toString() ?? ""
    }

     
     
    static func describeException(_ exception: JSValue?) -> String {
        guard let exception, !isAbsent(exception) else { return "exception" }
        let text = exception.toString() ?? "exception"
        if exception.isObject, let line = exception.objectForKeyedSubscript("line"), line.isNumber {
            return #"\#(text) (line \#(line.toInt32()))"#
        }
        return text
    }
}
#endif
