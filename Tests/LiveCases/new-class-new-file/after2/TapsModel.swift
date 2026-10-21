import Combine
final class TapsModel: ObservableObject { @Published var taps = 0; var doubled: Int { taps * 2 } }
