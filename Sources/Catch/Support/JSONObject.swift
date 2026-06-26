import Foundation

struct JSONObject: @unchecked Sendable, ExpressibleByDictionaryLiteral {
    private let storage: [String: Any]

    init(_ storage: [String: Any]) {
        self.storage = storage
    }

    init(dictionaryLiteral elements: (String, Any)...) {
        storage = Dictionary(uniqueKeysWithValues: elements)
    }

    subscript(key: String) -> Any? {
        storage[key]
    }

    var rawValue: [String: Any] {
        Self.rawObject(storage) as? [String: Any] ?? [:]
    }

    private static func rawObject(_ value: Any) -> Any {
        if let object = value as? JSONObject {
            return object.rawValue
        }

        if let dictionary = value as? [String: Any] {
            return dictionary.mapValues(rawObject)
        }

        if let array = value as? [Any] {
            return array.map(rawObject)
        }

        return value
    }
}
