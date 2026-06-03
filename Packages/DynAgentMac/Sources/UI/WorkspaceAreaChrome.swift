import AppKit

enum WorkspaceAreaChrome {
    static func makeRootView(pinning splitView: NSSplitView) -> WorkspaceAreaRootView {
        configureRootSplit(splitView)
        let rootView = WorkspaceAreaRootView()
        rootView.pinnedSplitView = splitView
        rootView.addSubview(splitView)
        splitView.frame = rootView.bounds
        return rootView
    }

    static func configureRootSplit(_ splitView: NSSplitView) {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = true
        splitView.autoresizingMask = [.width, .height]
    }

    static func forceLayout(view: NSView, rootSplit: NSSplitView) {
        if let superview = view.superview, view.frame != superview.bounds {
            view.frame = superview.bounds
        }
        rootSplit.frame = view.bounds
        rootSplit.adjustSubviews()
        if rootSplit.arrangedSubviews.count == 1 {
            rootSplit.arrangedSubviews.first?.frame = rootSplit.bounds
        }
        view.layoutSubtreeIfNeeded()
    }

    static func metrics(view: NSView, rootSplit: NSSplitView) -> [String: Any] {
        [
            "workspaceViewWidth": Double(view.frame.width),
            "workspaceViewHeight": Double(view.frame.height),
            "workspaceRootWidth": Double(rootSplit.frame.width),
            "workspaceRootHeight": Double(rootSplit.frame.height),
            "workspaceRootSubviewFrames": rootSplit.arrangedSubviews.enumerated().map { index, view in
                [
                    "index": index,
                    "class": String(describing: type(of: view)),
                    "x": Double(view.frame.minX),
                    "y": Double(view.frame.minY),
                    "width": Double(view.frame.width),
                    "height": Double(view.frame.height),
                ] as [String: Any]
            },
        ]
    }
}
