import Testing
@testable import Ghostty

struct TestOutputParserTests {
    let parser = TestOutputParser()

    @Test
    func parsesJestOutput() {
        let text = """
        PASS  src/auth.test.ts
        FAIL  src/api.test.ts
          ● should return 200
            Expected: 200
            Received: 404
        Tests: 2 failed, 42 passed, 44 total
        Snapshots: 0 total
        Time:        3.45 s
        """

        let result = parser.parse(visibleText: text, scrollback: "")

        guard let output = result as? TestOutput else {
            Issue.record("Expected TestOutput")
            return
        }

        #expect(output.framework == "jest")
        #expect(output.passed == 42)
        #expect(output.failed == 2)
        #expect(output.failedTests.contains("src/api.test.ts"))
    }

    @Test
    func parsesPytestOutput() {
        let text = """
        ============================= test session starts ==============================
        collected 10 items
        test_auth.py::test_login PASSED                                        [ 10%]
        test_api.py::test_get_user FAILED                                      [ 20%]
        test_utils.py::test_format PASSED
        ============================== 1 failed, 9 passed in 2.34s ===============================
        """

        let result = parser.parse(visibleText: text, scrollback: "")

        guard let output = result as? TestOutput else {
            Issue.record("Expected TestOutput")
            return
        }

        #expect(output.framework == "pytest")
        #expect(output.passed == 9)
        #expect(output.failed == 1)
    }

    @Test
    func parsesCargoTestOutput() {
        let text = """
        running 3 tests
        test auth::tests::test_login ... ok
        test api::tests::test_get_user ... FAILED
        test utils::tests::test_format ... ok
        failures:
            api::tests::test_get_user
        test result: FAILED. 2 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.02s
        """

        let result = parser.parse(visibleText: text, scrollback: "")

        guard let output = result as? TestOutput else {
            Issue.record("Expected TestOutput")
            return
        }

        #expect(output.framework == "cargo")
        #expect(output.passed == 2)
        #expect(output.failed == 1)
        #expect(output.failedTests.contains("api::tests::test_get_user"))
    }

    @Test
    func returnsNilForNonTestOutput() {
        let result = parser.parse(visibleText: "Hello world\n$", scrollback: "")
        #expect(result == nil)
    }
}
