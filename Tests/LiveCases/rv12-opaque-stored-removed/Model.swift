struct Box {
    private var payload: some Equatable = "value"
    var count = 7
    func describe() -> String { "payload=\(payload) count=\(count)" }
}
