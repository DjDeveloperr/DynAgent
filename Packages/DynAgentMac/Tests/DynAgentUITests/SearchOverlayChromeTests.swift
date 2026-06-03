import AppKit
@testable import DynAgentUI
import XCTest

@MainActor
final class SearchOverlayChromeTests: XCTestCase {
    func testPanelAndBackdropChrome() {
        let panel = SearchOverlayChrome.makePanel()

        XCTAssertEqual(panel.frame.size.width, SearchOverlayChrome.panelSize.width, accuracy: 0.5)
        XCTAssertEqual(panel.frame.size.height, SearchOverlayChrome.panelSize.height, accuracy: 0.5)
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(panel.level, .floating)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertTrue(panel.hidesOnDeactivate)

        var escaped = false
        panel.onEscape = { escaped = true }
        panel.cancelOperation(nil)
        XCTAssertTrue(escaped)

        var dismissed = false
        let root = SearchOverlayChrome.makeBackdrop { dismissed = true }
        XCTAssertTrue(root.wantsLayer)
        XCTAssertNotNil(root.layer?.backgroundColor)
        root.onOutsideClick?()
        XCTAssertTrue(dismissed)
    }

    func testFieldScrollAndStackChrome() {
        let delegate = FieldDelegate()
        let field = PaddedSearchField()
        var escaped = false

        SearchOverlayChrome.configureField(field, delegate: delegate) { escaped = true }

        XCTAssertEqual(field.placeholderString, "Search chats")
        XCTAssertEqual(field.font, .systemFont(ofSize: 18, weight: .regular))
        XCTAssertTrue(field.cell is PaddedSearchFieldCell)
        XCTAssertEqual(field.focusRingType, .none)
        XCTAssertTrue(field.delegate === delegate)
        XCTAssertFalse(field.translatesAutoresizingMaskIntoConstraints)
        field.cancelOperation(nil)
        XCTAssertTrue(escaped)

        var scrolled = false
        let scroll = SearchOverlayChrome.makeScroll { scrolled = true }
        XCTAssertFalse(scroll.drawsBackground)
        XCTAssertTrue(scroll.hasVerticalScroller)
        XCTAssertFalse(scroll.translatesAutoresizingMaskIntoConstraints)
        scroll.onScroll?()
        XCTAssertTrue(scrolled)

        let document = FlippedView()
        let stack = NSStackView()
        SearchOverlayChrome.configureStack(stack, in: document)
        XCTAssertEqual(stack.orientation, .vertical)
        XCTAssertEqual(stack.alignment, .leading)
        XCTAssertEqual(stack.spacing, 4)
        XCTAssertTrue(document.subviews.contains(stack))
        XCTAssertFalse(document.translatesAutoresizingMaskIntoConstraints)
        XCTAssertFalse(stack.translatesAutoresizingMaskIntoConstraints)
    }

    func testRootConstraintsUseOverlayConstants() {
        let root = SearchOverlayChrome.makeBackdrop {}
        let card = SearchOverlayChrome.makeCard()
        let field = PaddedSearchField()
        let scroll = SearchOverlayChrome.makeScroll {}
        let document = FlippedView()
        let stack = NSStackView()

        root.addSubview(card)
        card.addSubview(field)
        card.addSubview(scroll)
        document.addSubview(stack)

        let constraints = SearchOverlayChrome.rootConstraints(
            root: root,
            card: card,
            field: field,
            scroll: scroll,
            document: document,
            stack: stack
        )

        XCTAssertTrue(constraints.contains { $0.firstItem === card && $0.firstAttribute == .width && $0.constant == SearchOverlayChrome.cardSize.width })
        XCTAssertTrue(constraints.contains { $0.firstItem === card && $0.firstAttribute == .height && $0.constant == SearchOverlayChrome.cardSize.height })
        XCTAssertTrue(constraints.contains { $0.firstItem === card && $0.firstAttribute == .top && $0.constant == SearchOverlayChrome.cardTop })
        XCTAssertTrue(constraints.contains { $0.firstItem === field && $0.firstAttribute == .height && $0.constant == SearchOverlayChrome.fieldHeight })
        XCTAssertTrue(constraints.contains { $0.firstItem === field && $0.firstAttribute == .leading && $0.constant == 18 })
        XCTAssertTrue(constraints.contains { $0.firstItem === scroll && $0.firstAttribute == .leading && $0.constant == 8 })
    }

    func testResultRowBuildsTitleAndDetail() {
        let row = SearchOverlayChrome.makeRow(
            model: SearchOverlayRowModel(title: "Storage Cleanup", detail: "dynamic_agent"),
            onClick: {}
        )

        let labels = row.descendantTextFields()
        XCTAssertEqual(labels.map(\.stringValue), ["Storage Cleanup", "dynamic_agent"])
        XCTAssertEqual(labels[0].font, .systemFont(ofSize: 14, weight: .medium))
        XCTAssertEqual(labels[0].lineBreakMode, .byTruncatingTail)
        XCTAssertEqual(labels[0].maximumNumberOfLines, 1)
        XCTAssertEqual(labels[1].font, .systemFont(ofSize: 11.5))
        XCTAssertEqual(labels[1].textColor, .tertiaryLabelColor)
        XCTAssertEqual(labels[1].lineBreakMode, .byTruncatingTail)
        XCTAssertEqual(labels[1].maximumNumberOfLines, 1)
    }
}

private final class FieldDelegate: NSObject, NSSearchFieldDelegate {}

private extension NSView {
    func descendantTextFields() -> [NSTextField] {
        var result: [NSTextField] = []
        for subview in subviews {
            if let field = subview as? NSTextField {
                result.append(field)
            }
            result.append(contentsOf: subview.descendantTextFields())
        }
        return result
    }
}
