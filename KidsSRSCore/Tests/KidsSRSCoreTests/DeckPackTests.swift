import XCTest
@testable import KidsSRSCore

final class DeckPackTests: XCTestCase {

    func testDecodesDeckPackJSON() throws {
        let json = """
        {
          "id": "DEC00001-0000-0000-0000-000000000001",
          "title": "Spanish — Animals",
          "subjectTag": "spanish",
          "version": 1,
          "cards": [
            { "id": "CA000001-0000-0000-0000-000000000001",
              "front": "el gato", "back": "the cat", "hint": "a feline" },
            { "id": "CA000001-0000-0000-0000-000000000002",
              "front": "el perro", "back": "the dog", "hint": null }
          ]
        }
        """
        let pack = try JSONDecoder().decode(DeckPack.self, from: Data(json.utf8))

        XCTAssertEqual(pack.id, UUID(uuidString: "DEC00001-0000-0000-0000-000000000001"))
        XCTAssertEqual(pack.title, "Spanish — Animals")
        XCTAssertEqual(pack.subjectTag, "spanish")
        XCTAssertEqual(pack.version, 1)
        XCTAssertEqual(pack.cards.count, 2)
        XCTAssertEqual(pack.cards.first?.front, "el gato")
        XCTAssertEqual(pack.cards.first?.hint, "a feline")
        XCTAssertNil(pack.cards.last?.hint)
    }

    func testDecodesArrayOfPacks() throws {
        let json = """
        [
          { "id": "DEC00001-0000-0000-0000-000000000001", "title": "A", "subjectTag": null,
            "version": 1, "cards": [] },
          { "id": "DEC00001-0000-0000-0000-000000000002", "title": "B", "subjectTag": "math",
            "version": 2, "cards": [] }
        ]
        """
        let packs = try JSONDecoder().decode([DeckPack].self, from: Data(json.utf8))
        XCTAssertEqual(packs.map(\.title), ["A", "B"])
        XCTAssertNil(packs.first?.subjectTag)
        XCTAssertEqual(packs.last?.version, 2)
    }

    func testRoundTrips() throws {
        let pack = DeckPack(id: UUID(), title: "Deck", subjectTag: nil, version: 1,
                            cards: [CardPack(id: UUID(), front: "f", back: "b", hint: nil)])
        let data = try JSONEncoder().encode(pack)
        XCTAssertEqual(try JSONDecoder().decode(DeckPack.self, from: data), pack)
    }
}
