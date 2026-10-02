import Foundation
import SwiftData

@Model
final class PlaceFeedback {
    var id: UUID = UUID()
    var mapItemIdentifier: String = ""
    var placeName: String = ""
    var note: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var syncState: String = "pending"

    init(
        id: UUID = UUID(),
        mapItemIdentifier: String,
        placeName: String,
        note: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        syncState: String = "pending"
    ) {
        self.id = id
        self.mapItemIdentifier = mapItemIdentifier
        self.placeName = placeName
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncState = syncState
    }
}
