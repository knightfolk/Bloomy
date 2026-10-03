import Foundation
import Testing
@testable import DarkbloomTelemetry

struct EventPrivacyTests {
    @Test("privacy output matches the original filter across operational and sensitive fields")
    func filterParity() {
        for event in Self.parityEvents {
            #expect(EventPrivacy.sanitize(event) == EventPrivacyReference.sanitize(event))
            let sanitized = EventPrivacy.sanitize(event)
            #expect(EventPrivacy.sanitize(sanitized) == sanitized)
        }
    }

    @Test("shared privacy filters are deterministic across concurrent readers")
    func concurrentFiltering() async {
        let events = Self.parityEvents
        let expected = events.map(EventPrivacyReference.sanitize)
        await withTaskGroup(of: [LogEvent].self) { group in
            for _ in 0..<32 { group.addTask { events.map(EventPrivacy.sanitize) } }
            for await result in group { #expect(result == expected) }
        }
    }

    private static var parityEvents: [LogEvent] {
        let values = [
            "Loaded model; prompt_tokens=10 completion_tokens=20",
            "\u{1b}[31mAuthorization\u{1b}[0m: Bearer fixture-secret",
            "\u{1b}]8;;https://example.invalid\u{7}warning\u{1b}]8;;\u{7}",
            "\u{1b}]8;;https://example.invalid\u{1b}\\warning\u{1b}]8;;\u{1b}\\",
            "\u{1b}MApi\u{200B}_key=fixture-secret", "API-KEY: fixture-secret",
            "refresh token=fixture-secret", "account_id=fixture-account", "provider-key=fixture-provider",
            #"{"token":"fixture-secret"}"#, "token = fixture-secret", "completion: fixture-content",
            "requestsServed=123 tokens_generated=456", "Waiting for model inventory", "", "🙂 warning café e\u{301}",
            "see https://example.invalid/private and custom+scheme://hidden", "/Users/fixture-user/models",
            "/home/fixture-user/bin/provider", FileManager.default.homeDirectoryForCurrentUser.path + "/models",
            "prompt: fixture-content", "request_body=fixture-content", "reasoning=fixture-content",
            "Secret\u{0000}=fixture-secret", "password=fixture-secret", "a newline\nbecomes visible"
        ]
        return values.enumerated().map { index, message in
            LogEvent(timestamp: Date(timeIntervalSince1970: Double(index)), severity: .warning,
                category: values[(index + 3) % values.count], message: message, source: .unified,
                processID: 42, processImage: values[(index + 7) % values.count])
        }
    }

    @Test("buffer withholds credential and customer-payload fields before retention")
    func privateFields() {
        for message in [
            "Authorization: Bearer fixture-secret",
            "api_key=fixture-secret",
            "access_\u{200B}token=fixture-secret",
            "prompt: fixture-customer-content",
            "response=fixture-customer-content",
            #"{"messages":[{"content":"fixture-customer-content"}]}"#,
            "provider_id=fixture-provider"
        ] {
            var buffer = EventBuffer(capacity: 10)
            buffer.insert([event(message)])
            #expect(buffer.events.count == 1)
            #expect(buffer.events.first?.message.contains("fixture-") == false)
        }
    }

    @Test("URL secrets and home paths cannot survive in retained metadata")
    func metadata() throws {
        var buffer = EventBuffer(capacity: 10)
        buffer.insert([LogEvent(timestamp: nil, severity: .warning,
            category: "https://example.invalid/?token=fixture-secret",
            message: "Failed opening /Users/fixture-user/models; see https://example.invalid/private",
            source: .unified, processID: 42, processImage: "/Users/fixture-user/bin/provider")])
        let retained = try #require(buffer.events.first)
        #expect(!retained.category.contains("fixture-secret"))
        #expect(!retained.message.contains("fixture-user"))
        #expect(!retained.message.contains("example.invalid"))
        #expect(retained.processImage?.contains("fixture-user") == false)
        #expect(retained.processID == 42)
    }

    @Test("ordinary operational counters survive and sanitization is idempotent")
    func operationalEvents() {
        var buffer = EventBuffer(capacity: 10)
        let original = event("Loaded model; prompt_tokens=10 completion_tokens=20; retry in 5 seconds")
        buffer.insert([original])
        #expect(buffer.events == [original])
        buffer.insert(buffer.events)
        #expect(buffer.events == [original])
    }

    private func event(_ message: String) -> LogEvent {
        LogEvent(timestamp: nil, severity: .warning, category: "Inference", message: message,
                 source: .legacy, processID: nil, processImage: nil)
    }
}
