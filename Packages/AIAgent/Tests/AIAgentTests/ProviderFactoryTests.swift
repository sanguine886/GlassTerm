@testable import AIAgent
import Foundation
import XCTest

final class ProviderFactoryTests: XCTestCase {
    func testFactoryProducesOpenAIAdapter() {
        let adapter = AIProviderAdapterFactory.make(kind: .openAICompatible, config: testConfig, apiKey: testAPIKey)
        XCTAssertTrue(adapter is OpenAICompatibleAdapter)
    }

    func testFactoryProducesAnthropicAdapter() {
        let anthropicConfig = AIProviderConfig(
            name: "Claude",
            kind: .anthropic,
            baseURL: "https://api.anthropic.com",
            model: "claude-sonnet-4-5",
            apiKeyRef: "k"
        )
        let adapter = AIProviderAdapterFactory.make(kind: .anthropic, config: anthropicConfig, apiKey: testAPIKey)
        XCTAssertTrue(adapter is AnthropicAdapter)
    }

    func testFactoryProducesGeminiAdapter() {
        let geminiConfig = AIProviderConfig(
            name: "Gemini",
            kind: .gemini,
            baseURL: "https://generativelanguage.googleapis.com",
            model: "gemini-2.0-flash",
            apiKeyRef: "k"
        )
        let adapter = AIProviderAdapterFactory.make(kind: .gemini, config: geminiConfig, apiKey: testAPIKey)
        XCTAssertTrue(adapter is GeminiAdapter)
    }

    func testProviderKindRawValues() {
        XCTAssertEqual(AIProviderKind.openAICompatible.rawValue, "openAICompatible")
        XCTAssertEqual(AIProviderKind.anthropic.rawValue, "anthropic")
        XCTAssertEqual(AIProviderKind.gemini.rawValue, "gemini")
    }

    func testRoundTripCodable() throws {
        let cases: [AIProviderKind] = [.openAICompatible, .anthropic, .gemini]
        for kind in cases {
            let data = try JSONEncoder().encode(kind)
            let roundTripped = try JSONDecoder().decode(AIProviderKind.self, from: data)
            XCTAssertEqual(roundTripped, kind)
        }
    }
}