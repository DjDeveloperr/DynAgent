@testable import DynAgentUI
import AppKit
import XCTest

@MainActor
final class GitPanelChromeTests: XCTestCase {
    func testHeaderConfiguresTitleBranchAndSeparator() {
        let branch = NSTextField(labelWithString: "main")

        let header = GitPanelChrome.makeHeader(branchLabel: branch)

        XCTAssertEqual(header.view.material, .contentBackground)
        XCTAssertEqual(header.view.blendingMode, .withinWindow)
        XCTAssertEqual(header.view.state, .active)
        XCTAssertEqual(header.titleLabel.stringValue, "Changes")
        XCTAssertEqual(header.titleLabel.font, .systemFont(ofSize: 14, weight: .semibold))
        XCTAssertEqual(branch.font, .monospacedSystemFont(ofSize: 11, weight: .regular))
        XCTAssertEqual(branch.textColor, .secondaryLabelColor)
        XCTAssertEqual(header.border.boxType, .separator)
        XCTAssertTrue(header.view.subviews.contains(header.titleLabel))
        XCTAssertTrue(header.view.subviews.contains(branch))
        XCTAssertTrue(header.view.subviews.contains(header.border))
    }

    func testScopeControlAndDiffScrollChrome() {
        let target = Target()
        let scope = NSSegmentedControl(labels: ["All", "Staged"], trackingMode: .selectOne, target: nil, action: nil)
        let scroll = NSScrollView()
        let document = NSView()

        GitPanelChrome.configureScopeControl(scope, target: target, action: #selector(Target.action))
        GitPanelChrome.configureDiffScroll(scroll, document: document)

        XCTAssertEqual(scope.selectedSegment, 0)
        XCTAssertTrue(scope.target === target)
        XCTAssertEqual(scope.action, #selector(Target.action))
        XCTAssertEqual(scope.controlSize, .small)
        XCTAssertFalse(scope.translatesAutoresizingMaskIntoConstraints)

        XCTAssertTrue(scroll.hasVerticalScroller)
        XCTAssertTrue(scroll.hasHorizontalScroller)
        XCTAssertTrue(scroll.autohidesScrollers)
        XCTAssertEqual(scroll.scrollerStyle, .overlay)
        XCTAssertTrue(scroll.documentView === document)
        XCTAssertEqual(scroll.borderType, .noBorder)
        XCTAssertFalse(scroll.drawsBackground)
        XCTAssertFalse(scroll.automaticallyAdjustsContentInsets)
        XCTAssertEqual(scroll.contentInsets.top, GitPanelChrome.diffTopInset)
        XCTAssertTrue(scroll.contentView.postsBoundsChangedNotifications)
    }

    func testContentStackAndRootConstraintsUsePanelConstants() {
        let root = NSView()
        let scroll = NSScrollView()
        let prBox = NSBox()
        let status = NSTextField(labelWithString: "")
        let branch = NSTextField(labelWithString: "main")
        let header = GitPanelChrome.makeHeader(branchLabel: branch)
        let diffHeader = NSView()

        GitPanelChrome.configureStatusLabel(status)
        GitPanelChrome.configurePRBox(prBox, label: NSTextField(wrappingLabelWithString: ""))
        let stack = GitPanelChrome.makeContentStack(diffScroll: scroll, prBox: prBox, statusLabel: status)
        let constraints = GitPanelChrome.rootConstraints(
            root: root,
            stack: stack,
            header: header,
            diffHeader: diffHeader,
            branchLabel: branch
        )

        XCTAssertEqual(stack.orientation, .vertical)
        XCTAssertEqual(stack.spacing, 8)
        XCTAssertEqual(stack.alignment, .centerX)
        XCTAssertEqual(stack.edgeInsets.bottom, 12)
        XCTAssertEqual(status.font, .systemFont(ofSize: 11))
        XCTAssertEqual(status.textColor, .tertiaryLabelColor)
        XCTAssertEqual(prBox.titlePosition, .noTitle)
        XCTAssertTrue(prBox.isHidden)
        XCTAssertTrue(constraints.contains {
            $0.firstAnchor == header.view.heightAnchor && $0.constant == GitPanelChrome.headerHeight
        })
        XCTAssertTrue(constraints.contains {
            $0.firstAnchor == diffHeader.heightAnchor && $0.constant == GitPanelChrome.stickyHeaderHeight
        })
        XCTAssertTrue(constraints.contains {
            $0.firstAnchor == header.titleLabel.leadingAnchor && $0.constant == 14
        })
    }

    private final class Target: NSObject {
        @objc func action() {}
    }
}
