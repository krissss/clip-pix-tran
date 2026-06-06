import SwiftUI

struct RelativeTimeText: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(date.relativeDisplayString(now: context.date))
        }
    }
}
