import Foundation

/// A chat view can disappear while setup keeps its send. Ownership belongs to the app, so a new view
/// of that chat sees the same lock, and a rename keeps the token until its captured request finishes.
struct PendingSubmissions {
    private var owners: [String: UUID] = [:]

    func contains(_ projectID: String) -> Bool { owners[projectID] != nil }

    mutating func begin(_ projectID: String) -> UUID? {
        guard owners[projectID] == nil else { return nil }
        let token = UUID()
        owners[projectID] = token
        return token
    }

    mutating func move(from oldID: String, to newID: String) {
        if let token = owners.removeValue(forKey: oldID) { owners[newID] = token }
    }

    mutating func end(_ token: UUID) {
        owners = owners.filter { $0.value != token }
    }
}
