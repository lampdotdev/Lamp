import SwiftUI

/// Today's finished sessions as small dots, filled ones for those done and open ones up to the next long break,
/// so the row always shows how far there is to go without a number to read.
struct TodayDots: View {
    var done: Int
    var every: Int

    private var slots: Int {
        let group = max(1, every)
        return (done / group + 1) * group
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<min(slots, 16), id: \.self) { index in
                Circle()
                    .fill(index < done ? Color.focus : Color.secondary.opacity(0.25))
                    .frame(width: 7, height: 7)
                    // A little space between each run toward a long break.
                    .padding(.leading, index > 0 && index % max(1, every) == 0 ? 4 : 0)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.4), value: done)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(done == 1 ? "1 session today" : "\(done) sessions today")
    }
}
