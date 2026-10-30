#if canImport(WebKit)
import WebKit

extension NetworkPolicy {
    /// What WebKit reaches out to on a page's behalf that no Content-Security-Policy covers, turned off for a page held to
    /// its sites: WebRTC (its STUN and TURN servers are whichever the page names), and a link's preconnect and prefetch,
    /// which look up a name and open a connection whose name, in the lookup and the TLS hello, is whatever the page
    /// spells. WebKit's switches for these aren't public: each is asked for by its name, and only where it's there.
    /// Returns the ones turned off. Call it before the web view is made.
    @MainActor @discardableResult
    public static func holdBack(_ preferences: WKPreferences) -> [String] {
        let off: Set<String> = ["PeerConnectionEnabled", "LinkPreconnect", "LinkPreconnectEarlyHintsEnabled",
                                "LinkPrefetchEnabled", "SpeculationRulesPrefetchEnabled"]
        let list = NSSelectorFromString("_features"), set = NSSelectorFromString("_setEnabled:forFeature:")
        let type: AnyObject = WKPreferences.self
        guard type.responds(to: list), preferences.responds(to: set),
              let features = type.perform(list)?.takeUnretainedValue() as? [NSObject] else { return [] }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
        let setEnabled = unsafeBitCast(preferences.method(for: set), to: Setter.self)
        var done: [String] = []
        for feature in features {
            guard let key = feature.value(forKey: "key") as? String, off.contains(key) else { continue }
            setEnabled(preferences, set, false, feature)
            done.append(key)
        }
        return done.sorted()
    }
}
#endif
