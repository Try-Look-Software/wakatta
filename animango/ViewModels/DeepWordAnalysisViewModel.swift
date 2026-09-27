import Foundation
import SwiftData

@Observable @MainActor
final class DeepWordAnalysisViewModel {

    // MARK: - State

    var inputText: String = ""
    var analysisResult: WordAnalysisResult?
    var isAnalyzing: Bool = false
    var errorMessage: String?
    var showFurigana: Bool = true

    var isConfigured: Bool { analysisService.isConfigured }

    // MARK: - Private

    private let analysisService = WordAnalysisService()
    private let jishoService = JishoService()

    // MARK: - Configuration

    func configure(modelContext: ModelContext) {
        analysisService.configure(modelContext: modelContext)
    }

    // MARK: - Analysis

    func analyzeWord() async {
        let word = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }

        isAnalyzing = true
        errorMessage = nil
        analysisResult = nil

        do {
            // Run LLM analysis and Jisho lookup in parallel
            async let llmAnalysis = analysisService.analyze(word: word)
            async let jishoResults = jishoService.searchWords(keyword: word)

            let llmResult = try await llmAnalysis
            let jishoData = try? await jishoResults

            // Extract JLPT and part of speech from Jisho
            let jlptLevel: Int?
            let partOfSpeech: String?
            if let firstWord = jishoData?.first {
                let vocabData = jishoService.toVocabularyData(firstWord)
                jlptLevel = vocabData.jlpt
                partOfSpeech = vocabData.partOfSpeech
            } else {
                jlptLevel = nil
                partOfSpeech = nil
            }

            // Build conjugation info
            let conjugation: ConjugationInfo?
            if let conj = llmResult.conjugation {
                conjugation = ConjugationInfo(
                    currentForm: conj.currentForm,
                    dictionaryForm: llmResult.dictionaryForm,
                    verbType: conj.verbType,
                    ruleExplanation: conj.ruleExplanation,
                    conjugationSteps: conj.steps
                )
            } else {
                conjugation = nil
            }

            // Build kanji breakdown
            let kanjiBreakdown = (llmResult.kanjiBreakdown ?? []).map { kanji in
                KanjiAnalysis(
                    character: kanji.character,
                    meanings: kanji.meanings,
                    onReadings: kanji.onReadings ?? [],
                    kunReadings: kanji.kunReadings ?? []
                )
            }

            // Build example sentences
            let exampleSentences = (llmResult.exampleSentences ?? []).map { example in
                AnimeExampleSentence(
                    japanese: example.japanese,
                    reading: example.reading,
                    english: example.english,
                    source: example.source,
                    sourceType: example.sourceType
                )
            }

            analysisResult = WordAnalysisResult(
                inputWord: word,
                dictionaryForm: llmResult.dictionaryForm,
                reading: llmResult.reading,
                translation: llmResult.translation,
                conjugation: conjugation,
                kanjiBreakdown: kanjiBreakdown,
                exampleSentences: exampleSentences,
                jlptLevel: jlptLevel,
                partOfSpeech: partOfSpeech
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isAnalyzing = false
    }

    func clear() {
        inputText = ""
        analysisResult = nil
        errorMessage = nil
    }
}
