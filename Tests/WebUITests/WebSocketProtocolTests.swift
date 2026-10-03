import Testing
import Foundation
@testable import WebUI

// MARK: - FragmentOp round-trips (t1.1: remove/attr/move added beside append/text)

@Test("FragmentUpdate.remove round-trips")
func fragmentRemoveRoundTrip() throws {
    let update = FragmentUpdate.remove(id: "row-3")
    let back = try JSONDecoder().decode(FragmentUpdate.self, from: try JSONEncoder().encode(update))
    #expect(back.op == .remove)
    #expect(back.id == "row-3")
    let json = String(data: try JSONEncoder().encode(update), encoding: .utf8)!
    #expect(json.contains("\"op\":\"remove\""))
}

@Test("FragmentUpdate.attr round-trips name and value")
func fragmentAttrRoundTrip() throws {
    let update = FragmentUpdate.attr(id: "row-1", name: "aria-selected", value: "true")
    let back = try JSONDecoder().decode(FragmentUpdate.self, from: try JSONEncoder().encode(update))
    #expect(back.op == .attr)
    #expect(back.id == "row-1")
    #expect(back.name == "aria-selected")
    #expect(back.value == "true")
    let json = String(data: try JSONEncoder().encode(update), encoding: .utf8)!
    #expect(json.contains("\"name\":\"aria-selected\""))
    #expect(json.contains("\"value\":\"true\""))
}

@Test("FragmentUpdate.move round-trips before anchor")
func fragmentMoveRoundTrip() throws {
    let withAnchor = FragmentUpdate.move(id: "li-4", before: "li-2")
    let anchoredBack = try JSONDecoder().decode(FragmentUpdate.self, from: try JSONEncoder().encode(withAnchor))
    #expect(anchoredBack.op == .move)
    #expect(anchoredBack.before == "li-2")
    let json = String(data: try JSONEncoder().encode(withAnchor), encoding: .utf8)!
    #expect(json.contains("\"op\":\"move\""))
    #expect(json.contains("\"before\":\"li-2\""))

    let toEnd = FragmentUpdate.move(id: "li-4")
    let endBack = try JSONDecoder().decode(FragmentUpdate.self, from: try JSONEncoder().encode(toEnd))
    #expect(endBack.op == .move)
    #expect(endBack.before == nil)
}

@Test("Absent op decodes replace (the pin)")
func absentOpDecodesReplace() throws {
    let legacy = Data("{\"id\":\"legacy\",\"html\":\"<p>L</p>\"}".utf8)
    let back = try JSONDecoder().decode(FragmentUpdate.self, from: legacy)
    #expect(back.op == nil)
    #expect(back.name == nil)
    #expect(back.value == nil)
    #expect(back.text == nil)
}

@Test("New-op jsonText agrees with Codable (data-free wire)")
func newOpJsonTextWire() throws {
    func wire(_ fragment: FragmentUpdate) -> String {
        WSOutgoing.update(fragments: [fragment]).jsonText
    }
    let remove = wire(FragmentUpdate.remove(id: "x"))
    #expect(remove.contains("\"op\":\"remove\""))
    let attr = wire(FragmentUpdate.attr(id: "x", name: "data-state", value: "on"))
    #expect(attr.contains("\"op\":\"attr\""))
    #expect(attr.contains("\"name\":\"data-state\""))
    #expect(attr.contains("\"value\":\"on\""))
    let move = wire(FragmentUpdate.move(id: "x", before: "y"))
    #expect(move.contains("\"op\":\"move\""))
    #expect(move.contains("\"before\":\"y\""))
    let moveEnd = wire(FragmentUpdate.move(id: "x"))
    #expect(moveEnd.contains("\"op\":\"move\""))
    #expect(!moveEnd.contains("\"before\""))
}
