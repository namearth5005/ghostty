import Testing
@testable import Ghostty

struct GitStatusParserTests {
    let parser = GitStatusParser()

    @Test
    func parsesCleanGitStatus() {
        let text = """
        On branch main
        Your branch is up to date with 'origin/main'.

        nothing to commit, working tree clean
        """

        let result = parser.parse(visibleText: text, scrollback: "")

        guard let output = result as? GitStatusOutput else {
            Issue.record("Expected GitStatusOutput")
            return
        }

        #expect(output.branch == "main")
        #expect(output.ahead == 0)
        #expect(output.behind == 0)
        #expect(output.modifiedFiles == 0)
        #expect(output.untrackedFiles == 0)
        #expect(output.isMergeConflict == false)
    }

    @Test
    func parsesDirtyGitStatus() {
        let text = """
        On branch feature/auth
        Your branch is ahead of 'origin/feature/auth' by 2 commits.
          (use "git push" to publish your local commits)

        Changes not staged for commit:
          (use "git add <file>..." to update what will be committed)
          modified:   src/auth.swift
          modified:   src/api.swift

        Untracked files:
          (use "git add <file>..." to include in what will be committed)
            notes.txt
            todo.md
        """

        let result = parser.parse(visibleText: text, scrollback: "")

        guard let output = result as? GitStatusOutput else {
            Issue.record("Expected GitStatusOutput")
            return
        }

        #expect(output.branch == "feature/auth")
        #expect(output.ahead == 2)
        #expect(output.behind == 0)
        #expect(output.modifiedFiles == 2)
        #expect(output.untrackedFiles == 2)
        #expect(output.isMergeConflict == false)
    }

    @Test
    func detectsMergeConflict() {
        let text = """
        On branch main
        You have unmerged paths.
          (fix conflicts and run "git commit")
          (use "git merge --abort" to abort the merge)

        Unmerged paths:
          (use "git add <file>..." to mark resolution)
            both modified:   src/conflict.swift
        """

        let result = parser.parse(visibleText: text, scrollback: "")

        guard let output = result as? GitStatusOutput else {
            Issue.record("Expected GitStatusOutput")
            return
        }

        #expect(output.isMergeConflict == true)
        #expect(output.branch == "main")
    }

    @Test
    func returnsNilForNonGitOutput() {
        let result = parser.parse(visibleText: "npm install\ndone", scrollback: "")
        #expect(result == nil)
    }
}
