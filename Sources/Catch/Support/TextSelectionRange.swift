import Foundation

struct TextSelectionRange: Equatable {
    var location: Int
    var length: Int

    init(location: Int = 0, length: Int = 0) {
        self.location = location
        self.length = length
    }

    init(_ range: NSRange) {
        location = range.location
        length = range.length
    }

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }

    func clamped(to text: String) -> NSRange {
        let textLength = (text as NSString).length
        let clampedLocation = min(max(0, location), textLength)
        let clampedLength = min(max(0, length), textLength - clampedLocation)
        return NSRange(location: clampedLocation, length: clampedLength)
    }
}
