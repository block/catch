import Foundation
import Testing
@testable import CatchKit

@Suite
struct FormattersTests {
    @Test
    func compactAgeRendersNowForTimestampsUnderOneMinute() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        #expect(AppFormatters.compactAge(for: now, relativeTo: now) == "now")
        #expect(AppFormatters.compactAge(for: now.addingTimeInterval(-59), relativeTo: now) == "now")
        #expect(AppFormatters.compactAge(for: now.addingTimeInterval(1), relativeTo: now) == "now")
    }

    @Test
    func compactAgeKeepsMinuteGranularityAtOneMinute() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        #expect(AppFormatters.compactAge(for: now.addingTimeInterval(-60), relativeTo: now) == "1m")
    }
}
