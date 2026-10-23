import XCTest
@testable import WhisperDrop

final class ProofreadingModelCatalogTests: XCTestCase {
    func testManifestsContainModelAndTokenizerWithIntegrityHashes() {
        let models = ProofreadingModelCatalog.models
        XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        XCTAssertEqual(Set(models.map(\.folderName)).count, models.count)
        for model in models {
            XCTAssertFalse(model.files.isEmpty)
            XCTAssertEqual(Set(model.files.map(\.path)).count, model.files.count)
            for path in ["model.safetensors", "tokenizer.json"] {
                let file = model.files.first { $0.path == path }
                XCTAssertNotNil(file, "\(model.id): \(path)")
                XCTAssertEqual(file?.sha256?.count, 64, "\(model.id): \(path)")
                XCTAssertNotNil(file?.sha256?.range(of: "^[a-f0-9]{64}$", options: .regularExpression))
            }
            for file in model.files {
                XCTAssertGreaterThan(file.size, 0)
            }
        }
    }

    func testDownloadSizesIncludeAllRequiredFiles() {
        let expected: [String: Int64] = [
            "qwen3.5-0.8b": 645_302_309,
            "qwen3.5-2b": 1_742_354_857,
            "qwen3.5-4b": 3_054_404_243,
            "gemma-4-e2b": 3_583_085_182,
        ]
        XCTAssertEqual(Set(ProofreadingModelCatalog.models.map(\.id)), Set(expected.keys))
        for (id, size) in expected {
            XCTAssertEqual(ProofreadingModelCatalog.model(id: id)?.size, size, id)
        }
    }

    func testLanguageDefaultsResolveToCatalogEntries() {
        for language in ["ru", "ru-RU", "en", "en-US", "de", ""] {
            XCTAssertEqual(ProofreadingModelCatalog.defaultModelID(forLanguage: language), "qwen3.5-4b")
            XCTAssertNotNil(ProofreadingModelCatalog.model(id: ProofreadingModelCatalog.defaultModelID(forLanguage: language)))
        }
        XCTAssertNil(ProofreadingModelCatalog.model(id: "unknown"))
    }
}
