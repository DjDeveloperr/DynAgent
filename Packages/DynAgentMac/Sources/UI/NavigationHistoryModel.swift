import Foundation

struct NavigationHistoryModel<Item: AnyObject> {
    private(set) var backStack: [Item] = []
    private(set) var forwardStack: [Item] = []
    var maxDepth = 50

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    mutating func recordLeaving(current: Item?, to next: Item?) {
        guard let current, current !== next else { return }
        backStack.removeAll { $0 === current }
        backStack.append(current)
        trimBackStack()
        forwardStack.removeAll()
    }

    mutating func goBack(from current: Item?) -> Item? {
        guard let target = backStack.popLast() else { return nil }
        if let current, current !== target {
            forwardStack.append(current)
        }
        return target
    }

    mutating func goForward(from current: Item?) -> Item? {
        guard let target = forwardStack.popLast() else { return nil }
        if let current, current !== target {
            backStack.append(current)
            trimBackStack()
        }
        return target
    }

    private mutating func trimBackStack() {
        guard maxDepth >= 0 else { return }
        if backStack.count > maxDepth {
            backStack.removeFirst(backStack.count - maxDepth)
        }
    }
}
