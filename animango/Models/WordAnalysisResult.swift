import Foundation

// MARK: - Display Models

struct WordAnalysisResult {
    let inputWord: String
    let dictionaryForm: String
    let reading: String
    let translation: String
    let conjugation: ConjugationInfo?
    let kanjiBreakdown: [KanjiAnalysis]
    let exampleSentences: [AnimeExampleSentence]
    let jlptLevel: Int?
    let partOfSpeech: String?
}

struct ConjugationInfo {
    let currentForm: String       // "て-form"
    let dictionaryForm: String    // "食べる"
    let verbType: String          // "Ichidan (る-verb)"
    let ruleExplanation: String   // "Drop る, add て"
    let conjugationSteps: [String] // ["食べる → 食べ → 食べて"]
}

struct KanjiAnalysis: Identifiable {
    let id: String
    let character: String         // "食"
    let meanings: [String]        // ["eat", "food"]
    let onReadings: [String]      // ["ショク"]
    let kunReadings: [String]     // ["た.べる"]
    let jlptLevel: Int?

    init(character: String, meanings: [String], onReadings: [String], kunReadings: [String], jlptLevel: Int? = nil) {
        self.id = UUID().uuidString
        self.character = character
        self.meanings = meanings
        self.onReadings = onReadings
        self.kunReadings = kunReadings
        self.jlptLevel = jlptLevel
    }
}

struct AnimeExampleSentence: Identifiable {
    let id: String
    let japanese: String          // "俺は肉を食べたい"
    let reading: String           // "おれはにくをたべたい"
    let english: String           // "I want to eat meat"
    let source: String            // "Shingeki no Kyojin"
    let sourceType: String        // "Anime"

    init(japanese: String, reading: String, english: String, source: String, sourceType: String) {
        self.id = UUID().uuidString
        self.japanese = japanese
        self.reading = reading
        self.english = english
        self.source = source
        self.sourceType = sourceType
    }
}

// MARK: - LLM Response Models (Codable for JSON parsing)

struct WordAnalysisLLMResponse: Codable {
    let translation: String
    let dictionaryForm: String
    let reading: String
    let conjugation: ConjugationLLMResponse?
    let kanjiBreakdown: [KanjiLLMResponse]?
    let exampleSentences: [ExampleSentenceLLMResponse]?
}

struct ConjugationLLMResponse: Codable {
    let currentForm: String
    let verbType: String
    let ruleExplanation: String
    let steps: [String]
}

struct KanjiLLMResponse: Codable {
    let character: String
    let meanings: [String]
    let onReadings: [String]?
    let kunReadings: [String]?
}

struct ExampleSentenceLLMResponse: Codable {
    let japanese: String
    let reading: String
    let english: String
    let source: String
    let sourceType: String
}
