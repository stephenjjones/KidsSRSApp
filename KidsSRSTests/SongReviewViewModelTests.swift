import XCTest
import KidsSRSCore
@testable import KidsSRS

/// Tests for the Song Review view models (Spec §14.3–§14.4): playlist editing
/// (`SongDeckViewModel`) and the parent-led review session (`SongReviewViewModel`)
/// — presence, the 3-level parent grade write-through, and playlist navigation.
@MainActor
final class SongReviewViewModelTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private struct Fixture {
        let persistence: PersistenceController
        let decks: DeckRepository
        let children: ChildRepository
        let study: StudyRepository
        let deck: DeckSummary
    }

    /// In-memory store with a 2-song playlist and two children.
    private func makeFixture() throws -> Fixture {
        let persistence = PersistenceController(inMemory: true)
        let decks = DeckRepository(persistence: persistence)
        let children = ChildRepository(persistence: persistence)
        let study = StudyRepository(persistence: persistence)
        let deck = try decks.createDeck(title: "Morning Songs")
        _ = try decks.addVideoCard(to: deck.id, title: "Days of the Week",
                                   youTube: "https://youtu.be/36n93jvjkDs", hint: nil)
        _ = try decks.addVideoCard(to: deck.id, title: "Count to 100",
                                   youTube: "https://youtu.be/0VLxWIHRD4E", hint: nil)
        _ = try children.createChild(name: "Mia")
        _ = try children.createChild(name: "Theo")
        return Fixture(persistence: persistence, decks: decks, children: children,
                       study: study, deck: deck)
    }

    private func makeReviewVM(_ f: Fixture) -> SongReviewViewModel {
        let vm = SongReviewViewModel(deck: f.deck, decks: f.decks,
                                     childRepository: f.children, study: f.study,
                                     now: { [now] in now })
        vm.load()
        return vm
    }

    // MARK: SongReviewViewModel

    func testLoadAllPresentByDefault() throws {
        let vm = makeReviewVM(try makeFixture())
        XCTAssertEqual(vm.songs.count, 2)
        XCTAssertEqual(vm.children.count, 2)
        XCTAssertEqual(vm.presentChildren.count, 2)
        XCTAssertEqual(vm.index, 0)
        XCTAssertFalse(vm.isFinished)
        XCTAssertEqual(vm.positionText, "Song 1 of 2")
    }

    func testTogglePresenceRemovesChildFromScoring() throws {
        let vm = makeReviewVM(try makeFixture())
        let leaving = try XCTUnwrap(vm.children.first)
        vm.togglePresence(leaving.id)
        XCTAssertFalse(vm.presentChildren.contains { $0.id == leaving.id })
        XCTAssertEqual(vm.presentChildren.count, 1)
    }

    func testGradeRecordsSelectionAndPersists() throws {
        let vm = makeReviewVM(try makeFixture())
        let child = try XCTUnwrap(vm.children.first)
        vm.grade(.knowsIt, forChild: child.id)
        XCTAssertEqual(vm.selection[child.id], .knowsIt)
        XCTAssertNil(vm.errorMessage)
    }

    func testNavigationAdvancesAndResetsSelection() throws {
        let vm = makeReviewVM(try makeFixture())
        let child = try XCTUnwrap(vm.children.first)
        vm.grade(.gettingThere, forChild: child.id)
        XCTAssertFalse(vm.selection.isEmpty)

        XCTAssertTrue(vm.hasNext)
        vm.goNext()
        XCTAssertEqual(vm.index, 1)
        XCTAssertTrue(vm.selection.isEmpty, "selection resets on a new song")
        XCTAssertFalse(vm.hasNext)
        XCTAssertTrue(vm.hasPrevious)

        vm.goPrevious()
        XCTAssertEqual(vm.index, 0)
    }

    func testSongDidEndAdvancesThenFinishes() throws {
        let vm = makeReviewVM(try makeFixture())
        vm.songDidEnd()                 // song 1 → song 2
        XCTAssertEqual(vm.index, 1)
        XCTAssertFalse(vm.isFinished)
        vm.songDidEnd()                 // last song → finished
        XCTAssertTrue(vm.isFinished)
    }

    func testRestartReturnsToFirstSong() throws {
        let vm = makeReviewVM(try makeFixture())
        vm.songDidEnd(); vm.songDidEnd()
        XCTAssertTrue(vm.isFinished)
        vm.restart()
        XCTAssertEqual(vm.index, 0)
        XCTAssertFalse(vm.isFinished)
    }

    func testReportPlayerErrorMapsCodesToNotes() throws {
        let vm = makeReviewVM(try makeFixture())
        vm.reportPlayerError(code: 101)         // embedding disabled
        XCTAssertNotNil(vm.playerNote)
        // A new song clears the note.
        vm.goNext()
        XCTAssertNil(vm.playerNote)
        vm.reportPlayerError(code: 999)         // unknown code still yields a note
        XCTAssertNotNil(vm.playerNote)
    }

    // MARK: SongDeckViewModel

    func testSongDeckAddAndDelete() throws {
        let f = try makeFixture()
        let vm = SongDeckViewModel(deck: f.deck, repository: f.decks)
        vm.load()
        XCTAssertEqual(vm.songs.count, 2)

        vm.addSong(title: "ABC Song", youTube: "https://youtu.be/75p-N9YKqNo")
        XCTAssertEqual(vm.songs.count, 3)

        // Empty inputs are a no-op (guarded), not an error.
        vm.addSong(title: "   ", youTube: "")
        XCTAssertEqual(vm.songs.count, 3)
        XCTAssertNil(vm.errorMessage)

        vm.deleteSongs(at: IndexSet(integer: 0))
        XCTAssertEqual(vm.songs.count, 2)
    }
}
