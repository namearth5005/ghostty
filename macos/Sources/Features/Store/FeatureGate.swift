import Foundation

enum Feature {
    case basicAI
    case multiSurface
    case memory
    case teamSync
}

enum FeatureGate {
    @MainActor
    static func check(_ feature: Feature) -> Bool {
        switch feature {
        case .basicAI:
            return true // Free tier allowed, but rate-limited
        case .multiSurface, .memory:
            return StoreManager.shared.isPro
        case .teamSync:
            return StoreManager.shared.isTeam
        }
    }

    @MainActor
    static func canUseBasicAI() -> Bool {
#if DEBUG
        return true
#endif
        let store = StoreManager.shared
        if store.isPro { return true }

        let defaults = UserDefaults.standard
        let key = "foreman.ai.dailyUsageCount"
        let dateKey = "foreman.ai.dailyUsageDate"

        let lastDate = defaults.object(forKey: dateKey) as? Date
        let today = Calendar.current.startOfDay(for: Date())

        if let lastDate = lastDate,
           Calendar.current.isDate(lastDate, inSameDayAs: today) {
            let count = defaults.integer(forKey: key)
            return count < 5
        } else {
            defaults.set(0, forKey: key)
            defaults.set(today, forKey: dateKey)
            return true
        }
    }

    @MainActor
    static func recordBasicAIUsage() {
        let defaults = UserDefaults.standard
        let key = "foreman.ai.dailyUsageCount"
        let dateKey = "foreman.ai.dailyUsageDate"

        let lastDate = defaults.object(forKey: dateKey) as? Date
        let today = Calendar.current.startOfDay(for: Date())

        if let lastDate = lastDate,
           Calendar.current.isDate(lastDate, inSameDayAs: today) {
            let count = defaults.integer(forKey: key)
            defaults.set(count + 1, forKey: key)
        } else {
            defaults.set(1, forKey: key)
            defaults.set(today, forKey: dateKey)
        }
    }

    static func dailyUsageCount() -> Int {
        let defaults = UserDefaults.standard
        let key = "foreman.ai.dailyUsageCount"
        let dateKey = "foreman.ai.dailyUsageDate"

        let lastDate = defaults.object(forKey: dateKey) as? Date
        let today = Calendar.current.startOfDay(for: Date())

        if let lastDate = lastDate,
           Calendar.current.isDate(lastDate, inSameDayAs: today) {
            return defaults.integer(forKey: key)
        }
        return 0
    }
}
