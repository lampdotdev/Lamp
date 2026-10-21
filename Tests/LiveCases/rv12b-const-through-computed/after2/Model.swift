enum Size {
    static var width: Int { 30 }
    static let half = width / 2
}
func half() -> Int { Size.half }
