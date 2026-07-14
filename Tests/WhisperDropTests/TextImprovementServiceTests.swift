import XCTest
@testable import WhisperDrop

final class TextImprovementServiceTests: XCTestCase {
    func testDecodesMarkedJSONArray() {
        let output = """
        Some model chatter
        OUTPUT_JSON:["Привет, мир.","Вторая строка."]
        """

        XCTAssertEqual(
            TextImprovementService.decodeModelOutput(output, expectedCount: 2),
            ["Привет, мир.", "Вторая строка."]
        )
    }

    func testDecodesMarkdownJSONArray() {
        let output = """
        ```json
        ["Hello.","Second."]
        ```
        """

        XCTAssertEqual(
            TextImprovementService.decodeModelOutput(output, expectedCount: 2),
            ["Hello.", "Second."]
        )
    }

    func testDecodesObjectOutputArray() {
        let output = """
        OUTPUT_JSON: {"output":["Исправлено.","Еще строка."]}
        """

        XCTAssertEqual(
            TextImprovementService.decodeModelOutput(output, expectedCount: 2),
            ["Исправлено.", "Еще строка."]
        )
    }

    func testDecodesMarkedJSONWithExtendedUnicode() {
        let output = """
        💬 Модель ответила: OUTPUT_JSON:["Привет 👋🏽","Кафе — уже открыто."] trailing text
        """

        XCTAssertEqual(
            TextImprovementService.decodeModelOutput(output, expectedCount: 2),
            ["Привет 👋🏽", "Кафе — уже открыто."]
        )
    }

    func testRejectsWrongCount() {
        XCTAssertNil(TextImprovementService.decodeModelOutput("OUTPUT_JSON:[\"Only one\"]", expectedCount: 2))
    }
}
