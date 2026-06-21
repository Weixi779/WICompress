import Foundation

/// Shared accessors for ImageIO property dictionaries (`[CFString: Any]`) used
/// across the test suites. Kept in one place so the test files don't each carry
/// their own copy.
extension Dictionary where Key == CFString, Value == Any {
    func intValue(for key: CFString) -> Int? {
        if let value = self[key] as? Int {
            return value
        }

        if let value = self[key] as? NSNumber {
            return value.intValue
        }

        return nil
    }

    func boolValue(for key: CFString) -> Bool? {
        if let value = self[key] as? Bool {
            return value
        }

        if let value = self[key] as? NSNumber {
            return value.boolValue
        }

        return nil
    }

    func dictionaryExists(for key: CFString) -> Bool {
        guard let dictionary = self[key] as? [AnyHashable: Any] else {
            return false
        }

        return !dictionary.isEmpty
    }
}
