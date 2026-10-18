import AppKit
import Testing
@testable import RayLite

@MainActor
struct NotePageTypographyTests {
    @Test(arguments: [
        ("", 0),
        ("Title", 5),
        ("Title\nBody\nMore body", 6),
        ("\nBody", 1),
        ("📝 Ideas\nBody", 9)
    ])
    func firstLineUsesUTF16Range(text: String, length: Int) {
        #expect(NotePageTypography.headingRange(in: text) == NSRange(location: 0, length: length))
    }

    @Test func firstLineAloneUsesHeadingStyle() throws {
        let text = NotePageTypography.text("Title\nBody\nMore body")
        let heading = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let body = try #require(text.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)
        let lastParagraph = try #require(text.attribute(.font, at: 11, effectiveRange: nil) as? NSFont)
        #expect(heading.pointSize == 56)
        #expect(body.pointSize == 16)
        #expect(lastParagraph == body)
        #expect(text.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor == NotePageTypography.textColor)
    }
}
