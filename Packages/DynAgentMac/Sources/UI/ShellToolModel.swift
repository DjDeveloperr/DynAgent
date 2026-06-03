import Foundation

struct ShellToolSummary: Equatable {
    var command: String
    var exitCode: String?
    var output: String
}

struct ShellToolTitle: Equatable {
    var action: String
    var detail: String?
    var monospacedDetail = false
    var category = "command"
}

enum ShellToolModel {
    static func summary(from detail: String?) -> ShellToolSummary {
        let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !detail.isEmpty else { return ShellToolSummary(command: "command", exitCode: nil, output: "") }
        let lines = detail.components(separatedBy: .newlines)
        if let commandIndex = lines.lastIndex(where: { $0.hasPrefix("$ ") }) {
            let command = String(lines[commandIndex].dropFirst(2))
            var exitCode: String?
            var outputStart = commandIndex + 1
            if lines.indices.contains(outputStart), lines[outputStart].hasPrefix("exit ") {
                exitCode = String(lines[outputStart].dropFirst(5))
                outputStart += 1
            }
            while lines.indices.contains(outputStart), lines[outputStart].isEmpty { outputStart += 1 }
            let output = outputStart < lines.count ? lines[outputStart...].joined(separator: "\n") : ""
            return ShellToolSummary(command: command, exitCode: exitCode, output: output)
        }
        let command = lines.first ?? detail
        let output = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return ShellToolSummary(command: command, exitCode: nil, output: output)
    }

    static func title(command: String, done: Bool) -> ShellToolTitle {
        guard !command.isEmpty else {
            return ShellToolTitle(action: done ? "Ran command" : "Running command")
        }
        let normalized = innerShellCommand(command) ?? command
        let words = shellWords(normalized)
        guard let executable = words.first?.split(separator: "/").last.map(String.init) else {
            return ShellToolTitle(action: done ? "Ran command" : "Running command")
        }
        let args = Array(words.dropFirst())
        switch executable {
        case "ls", "tree":
            return ShellToolTitle(action: done ? "Listed files" : "Listing files", detail: shellPathDetail(args).map { "in \($0)" }, category: "list")
        case "find", "fd":
            return ShellToolTitle(action: done ? "Searched files" : "Searching files", detail: shellPathDetail(args).map { "in \($0)" }, category: "search")
        case "rg", "grep", "ag":
            return ShellToolTitle(action: done ? "Searched for" : "Searching for", detail: shellSearchQuery(args), category: "search")
        case "cat", "sed", "head", "tail", "nl":
            return ShellToolTitle(action: done ? "Read" : "Reading", detail: shellPathDetail(args), category: "read")
        case "pwd":
            return ShellToolTitle(action: done ? "Checked working directory" : "Checking working directory")
        case "git":
            if args.first == "status" {
                return ShellToolTitle(action: done ? "Checked git status" : "Checking git status", category: "git")
            }
            if args.first == "diff" || args.first == "show" {
                return ShellToolTitle(action: done ? "Read diff" : "Reading diff", category: "diff")
            }
            if args.first == "grep" {
                return ShellToolTitle(action: done ? "Searched for" : "Searching for", detail: shellSearchQuery(Array(args.dropFirst())), category: "search")
            }
            return ShellToolTitle(action: done ? "Ran git" : "Running git", detail: args.first, category: "git")
        default:
            return ShellToolTitle(action: done ? "Ran command" : "Running command", detail: normalized, monospacedDetail: true)
        }
    }

    static func shellWords(_ command: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for ch in command {
            if escaped {
                current.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
                continue
            }
            if let q = quote {
                if ch == q { quote = nil }
                else { current.append(ch) }
                continue
            }
            if ch == "'" || ch == "\"" {
                quote = ch
            } else if ch == " " || ch == "\t" {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static func innerShellCommand(_ command: String) -> String? {
        let words = shellWords(command)
        guard let executable = words.first?.split(separator: "/").last.map(String.init),
              ["zsh", "bash", "sh", "fish"].contains(executable) else { return nil }
        for i in words.indices {
            let arg = words[i]
            guard arg == "-c" || arg == "-lc" || arg == "-lic" else { continue }
            let next = words.index(after: i)
            if words.indices.contains(next) { return words[next] }
        }
        return nil
    }

    private static func shellSearchQuery(_ args: [String]) -> String? {
        for arg in args where !arg.hasPrefix("-") && arg != "." {
            return arg
        }
        return nil
    }

    private static func shellPathDetail(_ args: [String]) -> String? {
        let ignoredOptionsWithValues: Set<String> = ["-n", "-m", "-C", "-A", "-B", "--max-count", "--context", "--after-context", "--before-context"]
        var skipNext = false
        var candidates: [String] = []
        for arg in args {
            if skipNext {
                skipNext = false
                continue
            }
            if ignoredOptionsWithValues.contains(arg) {
                skipNext = true
                continue
            }
            if arg.hasPrefix("-") { continue }
            candidates.append(arg)
        }
        return candidates.last
    }
}
