import XCTest
@testable import WhisperDrop

final class ProofreadingGuardTests: XCTestCase {
    /// A tiny stand-in dictionary so the tests don't depend on the system spell checker.
    private let dictionary: Set<String> = [
        "он", "сказал", "приезжайте", "в", "субботу", "мы", "долго", "искали", "маяк", "купил", "продал",
        "новый", "дом", "съемки", "заняли", "три", "дня", "снимали", "почти", "неделю", "да", "конечно",
        "я", "очень", "рад", "привет", "короткий", "короткие", "фильм", "фильмы", "местный", "рыбак", "рыбки",
        "потому", "что", "вообще",
    ]
    private func accept(_ original: String, _ corrected: String) -> String {
        ProofreadingGuard.accept(original: original, corrected: corrected) { self.dictionary.contains($0) }
    }

    func testRejectsGrammarChangeOfCorrectWords() {
        XCTAssertEqual(accept("короткий фильм", "короткие фильмы"), "короткий фильм")
        XCTAssertEqual(accept("местный рыбак", "местный рыбки"), "местный рыбак")
    }

    func testAcceptsSpacingOnlyJoinOrSplit() {
        XCTAssertEqual(accept("потомучто", "потому что"), "потому что")
        XCTAssertEqual(accept("потомучто", "потом мы"), "потомучто")
    }

    func testRealSpellCheckerKnowsRussian() async {
        let ok = await MainActor.run { SpellCheck.isRealWord("короткий") && !SpellCheck.isRealWord("сильнный") }
        XCTAssertTrue(ok)
    }

    func testAcceptsPunctuationAndCase() {
        XCTAssertEqual(
            accept("он сказал приезжайте в субботу", "Он сказал: приезжайте в субботу."),
            "Он сказал: приезжайте в субботу."
        )
    }

    func testAcceptsSpellingFix() {
        XCTAssertEqual(
            accept("мы долго искали мяак", "Мы долго искали маяк."),
            "Мы долго искали маяк."
        )
    }

    func testRejectsReplacedWord() {
        let original = "Он купил новый дом."
        XCTAssertEqual(accept(original, "Он продал новый дом."), original)
    }

    func testRejectsRewrittenSentence() {
        let original = "Съёмки заняли три дня."
        XCTAssertEqual(accept(original, "Мы снимали почти неделю."), original)
    }

    func testRejectsAddedWords() {
        let original = "Да, конечно."
        XCTAssertEqual(accept(original, "Да, конечно, я очень рад."), original)
    }

    func testKeepsOriginalForEmptyAnswer() {
        XCTAssertEqual(accept("Привет.", "  "), "Привет.")
    }
}
