import SwiftUI
struct ShareView: View {
    let items: [LampShare.Item]
    var body: some View { LampShareSheet(items:items) }
}
