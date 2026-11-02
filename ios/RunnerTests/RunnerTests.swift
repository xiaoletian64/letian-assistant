import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
  func testTrustedOrigin() {
    XCTAssertTrue(LetianURLRules.sameOrigin("https://example.test/a", "https://example.test:443/api"))
    XCTAssertFalse(LetianURLRules.sameOrigin("https://example.test:444/a", "https://example.test"))
    XCTAssertFalse(LetianURLRules.sameOrigin("https://other.test/a", "https://example.test"))
    XCTAssertFalse(LetianURLRules.sameOrigin("http://example.test/a", "https://example.test"))
    XCTAssertFalse(LetianURLRules.sameOrigin("https://user:pass@example.test/a", "https://example.test"))
    XCTAssertFalse(LetianURLRules.sameOrigin("https://example.test@evil.test", "https://example.test"))
  }
  func testPublicURLSchemes() {
    XCTAssertNotNil(LetianURLRules.external("weixin://"))
    XCTAssertNil(LetianURLRules.external("file:///private/test"))
    XCTAssertNil(LetianURLRules.external("https://u@example.test"))
    XCTAssertNil(LetianURLRules.external("javascript:alert(1)"))
  }
}
