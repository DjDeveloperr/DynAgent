import AppKit

protocol SearchOverlayPresenting: AnyObject {
    func show(over window: NSWindow)
}

extension SearchOverlayController: SearchOverlayPresenting {}

final class AppSearchOverlayCoordinator {
    typealias OverlayFactory = () -> any SearchOverlayPresenting

    private let makeOverlay: OverlayFactory
    private var currentOverlay: (any SearchOverlayPresenting)?

    init(makeOverlay: @escaping OverlayFactory) {
        self.makeOverlay = makeOverlay
    }

    func show(over window: NSWindow) {
        let overlay = makeOverlay()
        currentOverlay = overlay
        overlay.show(over: window)
    }
}
