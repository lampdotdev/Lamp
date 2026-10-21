enum Size {
    static var width: Int { 20 }
    static let half = width / 2
}
func half() -> Int { Size.half }
