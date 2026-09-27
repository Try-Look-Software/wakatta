import Foundation
import SwiftData

@Observable @MainActor
final class WordAnalysisService {

    private let llmManager = LLMServiceManager()

    var isConfigured: Bool { llmManager.isAvailable }

    func configure(modelContext: ModelContext) {
        llmManager.loadConfiguration(modelContext: modelContext)
    }

    /// Analyze a Japanese word or phrase using the LLM
    func analyze(word: String) async throws -> WordAnalysisLLMResponse {
        let systemPrompt = """
            You are a Japanese language analysis engine. Given a Japanese word or phrase, provide a comprehensive analysis.

            Respond ONLY with valid JSON in this exact format:
            {
              "translation": "English meaning(s)",
              "dictionaryForm": "dictionary form of the word",
              "reading": "full hiragana reading of the input word",
              "conjugation": {
                "currentForm": "name of the grammatical form used (e.g. て-form, past tense, passive, etc.)",
                "verbType": "verb/adjective classification (e.g. Ichidan/る-verb, Godan/う-verb, い-adjective, etc.)",
                "ruleExplanation": "clear explanation of how this form is created from the dictionary form",
                "steps": ["dictionary form → intermediate step → final form"]
              },
              "kanjiBreakdown": [
                {
                  "character": "漢",
                  "meanings": ["meaning1", "meaning2"],
                  "onReadings": ["カタカナ reading"],
                  "kunReadings": ["ひらがな reading"]
                }
              ],
              "exampleSentences": [
                {
                  "japanese": "Japanese sentence using the word",
                  "reading": "full hiragana reading of the sentence",
                  "english": "English translation",
                  "source": "Name of anime/manga/drama/movie",
                  "sourceType": "Anime"
                }
              ]
            }

            Important rules:
            - Set "conjugation" to null if the input is not a conjugated verb or adjective (e.g. for plain nouns, particles, or words already in dictionary form that aren't verbs/adjectives)
            - For kanjiBreakdown, include every kanji character that appears in the input word
            - If the input contains no kanji, set kanjiBreakdown to an empty array
            - For exampleSentences, provide 3-5 example sentences. Prefer real or realistic lines from popular anime, manga, J-drama, or Japanese movies. Include the source title and type (Anime, Manga, J-Drama, or Movie)
            - Do not include any text outside the JSON
            """

        let messages = [
            LLMMessage(role: .system, content: systemPrompt),
            LLMMessage(role: .user, content: word)
        ]

        let response = try await llmManager.chat(messages: messages)
        return try parseResponse(response)
    }

    // MARK: - Response Parsing

    private func parseResponse(_ response: String) throws -> WordAnalysisLLMResponse {
        let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract JSON from markdown code blocks if present
        let jsonString: String
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            let filtered = lines.filter { !$0.hasPrefix("```") }
            jsonString = filtered.joined(separator: "\n")
        } else {
            jsonString = cleaned
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw WordAnalysisError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(WordAnalysisLLMResponse.self, from: data)
        } catch {
            throw WordAnalysisError.parsingFailed(error.localizedDescription)
        }
    }
}

// MARK: - Errors

enum WordAnalysisError: LocalizedError {
    case invalidResponse
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Received an invalid response from the AI."
        case .parsingFailed(let detail):
            return "Failed to parse analysis: \(detail)"
        }
    }
}
