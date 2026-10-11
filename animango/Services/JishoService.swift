import Foundation

actor JishoService {
    private let client: APIClient
    private var lastRequestTime: Date?

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    // MARK: - Jisho API Response DTOs

    struct JishoResponse: Decodable {
        let data: [JishoWord]
    }

    struct JishoWord: Decodable {
        let slug: String
        let jlpt: [String]
        let japanese: [JishoReading]
        let senses: [JishoSense]
    }

    struct JishoReading: Decodable {
        let word: String?
        let reading: String?
    }

    struct JishoSense: Decodable {
        let english_definitions: [String]
        let parts_of_speech: [String]
    }

    // MARK: - Public API

    func searchWords(keyword: String) async throws -> [JishoWord] {
        await throttle()

        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://jisho.org/api/v1/search/words?keyword=\(encoded)") else {
            throw APIError.invalidURL
        }

        let response: JishoResponse = try await client.fetch(url)
        return response.data
    }

    /// Converts a JishoWord into vocabulary-compatible data
    nonisolated func toVocabularyData(_ word: JishoWord) -> (word: String, reading: String, meaning: String, jlpt: Int?, partOfSpeech: String?) {
        let wordText = word.japanese.first?.word ?? word.slug
        let reading = word.japanese.first?.reading ?? wordText
        let meaning = word.senses.first?.english_definitions.joined(separator: ", ") ?? ""

        let jlptLevel: Int? = {
            // Jisho returns JLPT tags like "jlpt-n5", "jlpt-n4", etc.
            guard let tag = word.jlpt.first else { return nil }
            let levelString = tag.replacingOccurrences(of: "jlpt-n", with: "")
            return Int(levelString)
        }()

        let partOfSpeech = word.senses.first?.parts_of_speech.first

        return (word: wordText, reading: reading, meaning: meaning, jlpt: jlptLevel, partOfSpeech: partOfSpeech)
    }

    // MARK: - Rate Limiting

    /// Ensures at least 1 second between requests to be respectful of Jisho's API
    private func throttle() async {
        if let lastTime = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < 1.0 {
                try? await Task.sleep(nanoseconds: UInt64((1.0 - elapsed) * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }
}
