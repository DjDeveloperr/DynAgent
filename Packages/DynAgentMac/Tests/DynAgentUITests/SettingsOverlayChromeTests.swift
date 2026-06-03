import AppKit
import XCTest
@testable import DynAgentUI

final class SettingsOverlayChromeTests: XCTestCase {
    func testConfigurePillAppliesLiquidSettingsButtonChrome() {
        let target = Target()
        let pill = NSVisualEffectView()
        let button = NSButton(title: "Settings", target: nil, action: nil)

        SettingsOverlayChrome.configurePill(
            pill,
            button: button,
            target: target,
            menuAction: #selector(Target.openMenu)
        )

        XCTAssertEqual(pill.material, .hudWindow)
        XCTAssertEqual(pill.blendingMode, .withinWindow)
        XCTAssertEqual(pill.state, .active)
        XCTAssertEqual(pill.layer?.cornerRadius, 14)
        XCTAssertEqual(pill.layer?.zPosition, 50)
        XCTAssertFalse(button.isBordered)
        XCTAssertEqual(button.imagePosition, .imageLeading)
        XCTAssertEqual(button.alignment, .left)
        XCTAssertTrue(button.target === target)
        XCTAssertEqual(button.action, #selector(Target.openMenu))
    }

    func testInstallPinsPillToHostBottomAndEmbedsButton() {
        let host = NSView()
        let pill = NSVisualEffectView()
        let button = NSButton(title: "Settings", target: nil, action: nil)
        SettingsOverlayChrome.configurePill(
            pill,
            button: button,
            target: Target(),
            menuAction: #selector(Target.openMenu)
        )

        SettingsOverlayChrome.install(pill, button: button, over: host)

        XCTAssertTrue(pill.superview === host)
        XCTAssertTrue(button.superview === pill)
        XCTAssertTrue(pill.constraints.contains { $0.firstAnchor == pill.heightAnchor && $0.constant == SettingsOverlayChrome.pillHeight })
    }

    func testMenuKeepsSettingsActionAndDisabledUsageRow() {
        let target = Target()
        let menu = SettingsOverlayChrome.makeMenu(
            usageTitle: "Usage remaining: 12 / 20 credits",
            target: target,
            settingsAction: #selector(Target.openSettings)
        )

        XCTAssertEqual(menu.items.map(\.title), [
            "Settings",
            "Usage remaining: 12 / 20 credits",
        ])
        XCTAssertTrue(menu.items[0].target === target)
        XCTAssertEqual(menu.items[0].action, #selector(Target.openSettings))
        XCTAssertFalse(menu.items[1].isEnabled)
        XCTAssertNil(menu.items[1].action)
    }

    func testSettingsAlertUsesExpectedCopy() {
        let alert = SettingsOverlayChrome.makeSettingsAlert()

        XCTAssertEqual(alert.messageText, "Settings")
        XCTAssertEqual(alert.informativeText, "DynAgent settings will appear here as the native controls land.")
        XCTAssertEqual(alert.buttons.first?.title, "Done")
    }

    private final class Target: NSObject {
        @objc func openMenu() {}
        @objc func openSettings() {}
    }
}
