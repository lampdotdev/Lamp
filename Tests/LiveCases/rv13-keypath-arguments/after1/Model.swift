struct Box<T> { var value: T; var label: String { "\(value)!" } }
enum Paths {
    static func make<T>(_: T.Type) -> AnyKeyPath { \Box<T>.label }
    static func same(_ saved: AnyKeyPath) -> String {
        var junk: [AnyKeyPath] = []
        let equal = (0..<50).filter { _ in junk.append(make(String.self)); return make(Int.self) == saved }.count
        return "\(equal) of 50 equal, \(junk.count) made"
    }
}
