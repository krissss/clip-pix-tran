import Foundation

extension Date {
    var absoluteDisplayString: String {
        formatted(
            .dateTime
                .year()
                .month()
                .day()
                .hour()
                .minute()
                .second()
                .locale(Locale(identifier: LocalizationPreference.effectiveLanguageCode))
        )
    }

    func relativeDisplayString(now: Date = Date()) -> String {
        let interval = max(0, now.timeIntervalSince(self))

        if interval < 60 {
            return L10n.relativeJustNow
        }

        if interval < 3600 {
            return L10n.relativeMinutesAgo(Int(interval / 60))
        }

        if interval < 86_400 {
            return L10n.relativeHoursAgo(Int(interval / 3600))
        }

        if interval < 604_800 {
            return L10n.relativeDaysAgo(Int(interval / 86_400))
        }

        return absoluteDisplayString
    }
}
