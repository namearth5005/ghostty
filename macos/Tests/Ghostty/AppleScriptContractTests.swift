import Foundation
import Testing

struct AppleScriptContractTests {
    @Test
    func inputTextCommandRemainsDeclaredAndBound() throws {
        let testsDirectoryURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let macOSRootURL = testsDirectoryURL.deletingLastPathComponent().deletingLastPathComponent()
        let scriptingDefinitionURL = macOSRootURL.appendingPathComponent("Ghostty.sdef")
        let commandSourceURL = macOSRootURL
            .appendingPathComponent("Sources")
            .appendingPathComponent("Features")
            .appendingPathComponent("AppleScript")
            .appendingPathComponent("ScriptInputTextCommand.swift")

        let scriptingDefinition = try String(contentsOf: scriptingDefinitionURL, encoding: .utf8)
        let commandSource = try String(contentsOf: commandSourceURL, encoding: .utf8)

        #expect(scriptingDefinition.contains(#"<command name="input text""#))
        #expect(scriptingDefinition.contains(#"<cocoa class="GhosttyScriptInputTextCommand"/>"#))
        #expect(commandSource.contains("@objc(GhosttyScriptInputTextCommand)"))
    }
}
