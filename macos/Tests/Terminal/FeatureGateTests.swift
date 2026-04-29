import XCTest
@testable import Ghostty

final class FeatureGateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "foreman.ai.dailyUsageCount")
        UserDefaults.standard.removeObject(forKey: "foreman.ai.dailyUsageDate")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "foreman.ai.dailyUsageCount")
        UserDefaults.standard.removeObject(forKey: "foreman.ai.dailyUsageDate")
        super.tearDown()
    }

    @MainActor
    func testDailyUsageStartsAtZero() {
        XCTAssertEqual(FeatureGate.dailyUsageCount(), 0)
        XCTAssertTrue(FeatureGate.canUseBasicAI())
    }

    @MainActor
    func testDailyUsageRecordsUpToLimit() {
        for _ in 0..<5 {
            XCTAssertTrue(FeatureGate.canUseBasicAI())
            FeatureGate.recordBasicAIUsage()
        }
        XCTAssertEqual(FeatureGate.dailyUsageCount(), 5)
#if DEBUG
        XCTAssertTrue(FeatureGate.canUseBasicAI())
#else
        XCTAssertFalse(FeatureGate.canUseBasicAI())
#endif
    }

    @MainActor
    func testDailyUsageResetsOnNewDay() {
        FeatureGate.recordBasicAIUsage()
        FeatureGate.recordBasicAIUsage()
        FeatureGate.recordBasicAIUsage()
        FeatureGate.recordBasicAIUsage()
        FeatureGate.recordBasicAIUsage()
#if DEBUG
        XCTAssertTrue(FeatureGate.canUseBasicAI())
#else
        XCTAssertFalse(FeatureGate.canUseBasicAI())
#endif

        // Simulate yesterday
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        UserDefaults.standard.set(yesterday, forKey: "foreman.ai.dailyUsageDate")

        XCTAssertTrue(FeatureGate.canUseBasicAI())
        XCTAssertEqual(FeatureGate.dailyUsageCount(), 0)
    }
}
