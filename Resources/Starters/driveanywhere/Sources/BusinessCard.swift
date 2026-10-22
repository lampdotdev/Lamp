import SwiftUI

/// The card for the place you're driving past: what it is, where, whether it's open now.
struct BusinessCard: View {
    let info: BusinessInfo

    var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(info.name)
                    .font(.system(size: 17, weight: .heavy))
                    .lineLimit(1)
                Text(info.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                if let a = info.address {
                    Text(a).font(.system(size: 12))
                }
                if let s = info.status, let open = info.open {
                    Text(s)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(open ? Color(red: 0.4, green: 0.95, blue: 0.5) : Color(red: 1, green: 0.45, blue: 0.4))
                }
                if let c = info.contact {
                    Text(c).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                if let url = info.website, let site = info.site {
                    Link(destination: url) {
                        Text(site).underline()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1))
                    .lineLimit(1)
                    .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                }
            }
            .foregroundStyle(.white)
        .padding(.vertical, 12)
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .frame(width: 290, alignment: .leading)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(info.color).frame(width: 4).padding(.vertical, 10)
        }
    }
}
