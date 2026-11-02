import XCTest
@testable import Lamp

/// A GGUF model in the shared cache can be newer than the llama.cpp build Lamp pins. Lamp reads the names the model's
/// file gives and asks the build's library for them, so a model it can't run is never chosen, and a load that fails
/// anyway is said plainly.
final class LocalModelSupportTests: XCTestCase {
    /// A GGUF header (version 3, no tensors) with these key-value pairs, strings and arrays of strings only.
    private func gguf(_ pairs: [(String, Any)]) -> Data {
        var data = Data("GGUF".utf8)
        func int(_ value: UInt64, _ size: Int) { for i in 0..<size { data.append(UInt8(truncatingIfNeeded: value >> (8 * i))) } }
        func string(_ text: String) { int(UInt64(text.utf8.count), 8); data.append(contentsOf: text.utf8) }
        int(3, 4); int(0, 8); int(UInt64(pairs.count), 8)
        for (key, value) in pairs {
            string(key)
            switch value {
            case let text as String: int(8, 4); string(text)
            case let list as [String]: int(9, 4); int(8, 4); int(UInt64(list.count), 8); list.forEach(string)
            case let number as UInt32: int(4, 4); int(UInt64(number), 4)
            default: XCTFail("unsupported value")
            }
        }
        return data
    }

    func testTheHeaderGivesTheArchitectureAndPreTokenizer() {
        // The tokenizer's vocabulary comes before its pre-tokenizer here, as it can in a real file.
        let data = gguf([("general.architecture", "flint"), ("flint.block_count", UInt32(49)),
                         ("tokenizer.ggml.tokens", ["a", "b", "<|end|>"]), ("tokenizer.ggml.pre", "flint")])
        XCTAssertEqual(LocalModels.ggufNames(in: data), ["flint", "flint"])
    }

    func testAModelWithNoPreTokenizerGivesItsArchitecture() {
        XCTAssertEqual(LocalModels.ggufNames(in: gguf([("general.architecture", "qwen35moe")])), ["qwen35moe"])
    }

    func testAFileThatIsntGGUFGivesNothing() {
        XCTAssertEqual(LocalModels.ggufNames(in: Data("not a model".utf8)), [])
        let cut = gguf([("general.architecture", "flint")])
        XCTAssertEqual(LocalModels.ggufNames(in: cut.prefix(cut.count - 2)), [])
    }

    func testTheLibraryKnowsANameOnlyAsAStringOfItsOwn() {
        let library = Data([0x7f] + Array("\0llama\0qwen35moe\0gemma3\0".utf8))
        XCTAssertTrue(LlamaInstall.holds(library, "qwen35moe"))
        XCTAssertTrue(LlamaInstall.holds(library, "llama"))
        XCTAssertFalse(LlamaInstall.holds(library, "flint"))
        // The end or start of a longer name isn't the name.
        XCTAssertFalse(LlamaInstall.holds(library, "moe"))
        XCTAssertFalse(LlamaInstall.holds(library, "qwen35"))
    }

    func testAModelThatFailedToLoadIsSaidPlainly() {
        XCTAssertEqual(Provider.friendlyError("500: model name=flint-int4 failed to load", from: "Native Mac AI"),
                       ErrorMessages.localModelFailed)
        XCTAssertEqual(Provider.friendlyError(status: 500, reply: ["error": ["message": "model name=flint-int4 failed to load"]],
                                              from: "Native Mac AI"),
                       ErrorMessages.localModelFailed)
    }
}
