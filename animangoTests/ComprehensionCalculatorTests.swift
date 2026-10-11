import Foundation
import SwiftData
import Testing
@testable import animango

@MainActor
struct ComprehensionCalculatorTests {

    private let mediaID = "anime-16498"
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(
            for: MediaVocabulary.self, UserProgress.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func addWord(_ word: String, frequency: Int, media: String? = nil) {
        context.insert(MediaVocabulary(mediaExternalID: media ?? mediaID, vocabularyWord: word, frequency: frequency))
    }

    private func setKnowledge(_ word: String, _ state: KnowledgeState, type: StudyItemType = .vocabulary) {
        context.insert(UserProgress(itemID: word, itemType: type, knowledgeState: state))
    }

    private func comprehension() -> Double {
        ComprehensionCalculator.calculate(mediaExternalID: mediaID, modelContext: context)
    }

    // MARK: - Boundaries

    @Test func mediaWithNoVocabularyIsZero() {
        setKnowledge("巨人", .mastered)

        let result = comprehension()

        #expect(result == 0)
        #expect(!result.isNaN)
    }

    @Test func noKnownWordsIsZero() {
        addWord("巨人", frequency: 10)
        addWord("壁", frequency: 4)

        #expect(comprehension() == 0)
    }

    @Test func neverLearnedProgressCountsAsUnknown() {
        addWord("巨人", frequency: 10)
        setKnowledge("巨人", .neverLearned)

        #expect(comprehension() == 0)
    }

    @Test func allMasteredIsOneHundred() {
        addWord("巨人", frequency: 10)
        addWord("壁", frequency: 4)
        addWord("調査兵団", frequency: 1)
        for word in ["巨人", "壁", "調査兵団"] { setKnowledge(word, .mastered) }

        #expect(abs(comprehension() - 100) < 1e-9)
    }

    @Test func allZeroFrequenciesDoNotDivideByZero() {
        addWord("巨人", frequency: 0)
        addWord("壁", frequency: 0)
        setKnowledge("巨人", .mastered)

        let result = comprehension()

        #expect(result == 0)
        #expect(result.isFinite)
    }

    // MARK: - Weighting

    @Test func commonWordCountsMoreThanRareWord() {
        addWord("巨人", frequency: 9)
        addWord("調査兵団", frequency: 1)
        setKnowledge("巨人", .mastered)

        #expect(abs(comprehension() - 90) < 1e-9)
    }

    @Test func rareWordCountsLessThanCommonWord() {
        addWord("巨人", frequency: 9)
        addWord("調査兵団", frequency: 1)
        setKnowledge("調査兵団", .mastered)

        #expect(abs(comprehension() - 10) < 1e-9)
    }

    @Test(arguments: [
        (KnowledgeState.learning, 30.0),
        (.developing, 70.0),
        (.mastered, 100.0),
    ])
    func partialKnowledgeIsWeightedByState(state: KnowledgeState, expected: Double) {
        addWord("巨人", frequency: 5)
        setKnowledge("巨人", state)

        #expect(abs(comprehension() - expected) < 1e-9)
    }

    @Test func otherMediaVocabularyIsIgnored() {
        addWord("巨人", frequency: 1)
        addWord("海賊", frequency: 100, media: "anime-21")
        setKnowledge("巨人", .mastered)

        #expect(abs(comprehension() - 100) < 1e-9)
    }

    // MARK: - Known issues

    @Test func kanjiProgressDoesNotCountAsVocabulary() {
        // 日 is both a vocabulary word and a kanji. Only kanji progress exists here.
        addWord("日", frequency: 1)
        setKnowledge("日", .mastered, type: .kanji)

        withKnownIssue("calculate(...) matches UserProgress by itemID only and ignores itemType") {
            #expect(comprehension() == 0)
        }
    }
}
