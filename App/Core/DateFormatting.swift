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
                .locale(Locale(identifier: "zh_Hans_CN"))
        )
    }

    func relativeDisplayString(now: Date = Date()) -> String {
        let interval = max(0, now.timeIntervalSince(self))

        if interval < 60 {
            return "刚刚"
        }

        if interval < 3600 {
            return "\(Int(interval / 60))分钟前"
        }

        if interval < 86_400 {
            return "\(Int(interval / 3600))小时前"
        }

        if interval < 604_800 {
            return "\(Int(interval / 86_400))天前"
        }

        return absoluteDisplayString
    }
}
