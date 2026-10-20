import WebUIIslandWire

// MARK: - Typed Islands
//
// a typed island trades the string args object for a versioned binary frame:
// the input is a `IslandPayloadEncodable` value with an exact layout, encoded
// once on the server, carried through the engine untouched, and decoded on the
// island without a json parse. the output door is unchanged — sanitized html —
// because the dom stays the one rendering authority.
//
// siblings, not refinements (the same reasoning as `ResizableIsland`): `Island`
// and `TypedIsland` have different `render` signatures, `Island` is frozen
// surface, and a requirement added to either would silently no-op through
// existentials. each protocol names exactly one door.

/// same-Swift logic whose input crosses the wasm boundary as a versioned
/// binary frame (`IslandEnvelope`).
public protocol TypedIsland: Sendable {
	/// the payload type. both sides ship the same swift, so one type serves
	/// the host's encode and the island's decode.
	associatedtype Input: IslandPayloadEncodable & IslandPayloadDecodable
	/// the capability grant — the engine fetches
	/// `/__assets/webui-<name>.wasm` only when the page declares it.
	static var name: String { get }
	/// the region's output. runs server-side for the fallback and inside the
	/// wasm module for the mount; the engine sanitizes it either way.
	static func render(_ input: Input) -> String
}

/// a typed island whose output depends on its container width.
///
/// the engine re-invokes the module with the measured width merged into the
/// mount args (`{"frame":…,"width":774}`); server rendering passes `nil`.
public protocol TypedResizableIsland: Sendable {
	associatedtype Input: IslandPayloadEncodable & IslandPayloadDecodable
	static var name: String { get }
	/// `width` is the measured container width in css pixels, or `nil` when
	/// unknown (server render, no layout yet).
	static func render(_ input: Input, width: Int?) -> String
}

/// declares a typed island's capability and mounts a region for it.
///
/// the input is encoded into the region's `data-webui-args` as a base64 frame;
/// the server-rendered fallback is `I.render(input)` — the same swift the wasm
/// mount runs.
public struct TypedIslandRegion<I: TypedIsland>: View {
	private let input: I.Input

	public init(_ input: I.Input) {
		self.input = input
	}

	public func render(into buffer: inout HTMLBuffer) {
		buffer.append(islandRegionMarkup(
			name: I.name,
			argsJSON: islandFrameArgsJSON(IslandEnvelope.encode(input)),
			resize: false,
			fallback: I.render(input)
		))
	}
}

/// declares a typed resizable island's capability and mounts its region.
///
/// emits the resize watch flag alongside the frame; the fallback is
/// `I.render(input, width: nil)`.
public struct TypedResizableIslandRegion<I: TypedResizableIsland>: View {
	private let input: I.Input

	public init(_ input: I.Input) {
		self.input = input
	}

	public func render(into buffer: inout HTMLBuffer) {
		buffer.append(islandRegionMarkup(
			name: I.name,
			argsJSON: islandFrameArgsJSON(IslandEnvelope.encode(input)),
			resize: true,
			fallback: I.render(input, width: nil)
		))
	}
}