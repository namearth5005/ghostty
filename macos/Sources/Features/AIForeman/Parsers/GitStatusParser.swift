import Foundation

struct GitStatusParser: TerminalOutputParser {
    let commandHints = ["git status"]

    func parse(visibleText: String, scrollback: String) -> ParsedTerminalOutput? {
        let combined = visibleText + "\n" + scrollback

        let branchPattern = /On branch ([^\n]+)/
        guard let branchMatch = combined.firstMatch(of: branchPattern) else {
            return nil
        }
        let branch = String(branchMatch.output.1).trimmingCharacters(in: .whitespaces)

        let aheadPattern = /Your branch is ahead of ['"]?.+?['"]? by (\d+) commit/
        let behindPattern = /Your branch is behind ['"]?.+?['"]? by (\d+) commit/
        let ahead = combined.firstMatch(of: aheadPattern).flatMap { Int($0.output.1) } ?? 0
        let behind = combined.firstMatch(of: behindPattern).flatMap { Int($0.output.1) } ?? 0

        let modifiedPattern = /modified:\s+/
        let untrackedPattern = /Untracked files:/
        let modifiedFiles = combined.matches(of: modifiedPattern).count
        let untrackedFiles: Int
        if let untrackedRange = combined.firstRange(of: "Untracked files:") {
            let after = String(combined[untrackedRange.upperBound...])
            let nextSection = after.split(separator: "\n\n").first ?? ""
            untrackedFiles = nextSection.split(separator: "\n").filter { $0.hasPrefix("\t") }.count
        } else {
            untrackedFiles = 0
        }

        let isMergeConflict = combined.localizedCaseInsensitiveContains("merge conflict") ||
            combined.localizedCaseInsensitiveContains("unmerged paths")

        return GitStatusOutput(
            branch: branch,
            ahead: ahead,
            behind: behind,
            modifiedFiles: modifiedFiles,
            untrackedFiles: untrackedFiles,
            isMergeConflict: isMergeConflict
        )
    }
}
