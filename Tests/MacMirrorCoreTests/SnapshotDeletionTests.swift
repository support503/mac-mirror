import Foundation
import Testing
@testable import MacMirrorCore

struct SnapshotDeletionTests {
    @Test
    func deleteSnapshotRemovesFileFromStore() throws {
        let snapshot = Snapshot(
            name: "Delete Me",
            machineIdentifier: "machine-1",
            displaySignatures: [],
            windowTargets: []
        )

        let store = SnapshotStore()
        try store.saveSnapshot(snapshot)
        defer { try? store.deleteSnapshot(idOrName: snapshot.id.uuidString) }

        #expect(try store.listSnapshots().contains(where: { $0.id == snapshot.id }))

        try store.deleteSnapshot(idOrName: snapshot.id.uuidString)

        #expect(try store.listSnapshots().contains(where: { $0.id == snapshot.id }) == false)
    }
}
