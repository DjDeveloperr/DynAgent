import Foundation

final class ChatStreamRegistry<Task> {
    private var activeIds = Set<String>()
    private var tasks: [String: Task] = [:]
    private var stoppingIds = Set<String>()

    func isActive(_ id: String) -> Bool {
        activeIds.contains(id)
    }

    func setActive(_ active: Bool, id: String) {
        if active {
            activeIds.insert(id)
        } else {
            activeIds.remove(id)
        }
    }

    func setTask(_ task: Task, id: String) {
        tasks[id] = task
    }

    func task(for id: String) -> Task? {
        tasks[id]
    }

    func markStopping(_ id: String) {
        stoppingIds.insert(id)
    }

    func consumeStopping(_ id: String) -> Bool {
        stoppingIds.remove(id) != nil
    }

    func finish(_ id: String, preservingStopFlag: Bool = false) {
        activeIds.remove(id)
        tasks[id] = nil
        if !preservingStopFlag {
            stoppingIds.remove(id)
        }
    }
}
