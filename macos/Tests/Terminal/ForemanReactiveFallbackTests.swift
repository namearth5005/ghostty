import Testing
@testable import Ghostty

struct ForemanReactiveFallbackTests {
    @Test
    func waitingTextWithoutDraftDoesNotFallBackToChatReaction() {
        #expect(AppDelegate.shouldFallBackToForemanChat(
            afterDraftFor: .waitingText,
            draftedAttention: nil
        ) == false)
    }

    @Test
    func nonTextAttentionWithoutDraftCanFallBackToChatReaction() {
        #expect(AppDelegate.shouldFallBackToForemanChat(
            afterDraftFor: .error,
            draftedAttention: nil
        ) == true)
    }
}
