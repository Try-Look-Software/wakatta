import Foundation
import Testing
@testable import animango

@MainActor
struct SRSEngineTests {

    private func newProgress() -> UserProgress {
        UserProgress(itemID: "食べる", itemType: .vocabulary)
    }

    /// Applies the grades in order and returns the interval after each review.
    @discardableResult
    private func review(_ progress: UserProgress, _ grades: [SRSEngine.Grade]) -> [Int] {
        grades.map { SRSEngine.processReview(progress: progress, grade: $0).interval }
    }

    // MARK: - First review

    @Test func firstCorrectReviewSchedulesOneDayOut() throws {
        let progress = newProgress()

        SRSEngine.processReview(progress: progress, grade: .good)

        #expect(progress.interval == 1)
        #expect(progress.repetitions == 1)
        #expect(progress.knowledgeState == .learning)
        #expect(progress.lastReviewedDate != nil)
        let next = try #require(progress.nextReviewDate)
        let days = Calendar.current.dateComponents([.day], from: Date(), to: next).day ?? -1
        #expect((0...1).contains(days))
    }

    @Test func firstReviewFailedStaysInLearning() {
        let progress = newProgress()

        SRSEngine.processReview(progress: progress, grade: .again)

        #expect(progress.interval == 1)
        #expect(progress.repetitions == 0)
        #expect(progress.knowledgeState == .learning)
    }

    // MARK: - Correct answers grow the interval

    @Test func correctAnswersFollowSM2Schedule() {
        let progress = newProgress()

        let intervals = review(progress, [.good, .good, .good])

        // SM-2: 1 day, then 3 days, then previous interval × ease factor (3 × 2.5).
        #expect(intervals == [1, 3, 7])
    }

    @Test func repeatedCorrectAnswersKeepGrowingTheInterval() {
        let progress = newProgress()

        let intervals = review(progress, Array(repeating: .good, count: 8))

        for (previous, next) in zip(intervals, intervals.dropFirst()) {
            #expect(next > previous, "intervals: \(intervals)")
        }
    }

    @Test func easyGrowsFasterThanGoodAndHardGrowsSlower() {
        let warmUp: [SRSEngine.Grade] = [.good, .good]

        let hard = newProgress()
        review(hard, warmUp + [.hard])
        let good = newProgress()
        review(good, warmUp + [.good])
        let easy = newProgress()
        review(easy, warmUp + [.easy])

        #expect(hard.interval < good.interval)
        #expect(good.interval < easy.interval)
    }

    // MARK: - Ease factor

    @Test(arguments: [
        (SRSEngine.Grade.again, -0.8),
        (.hard, -0.14),
        (.good, 0.0),
        (.easy, 0.1),
    ])
    func easeFactorChangesByGrade(grade: SRSEngine.Grade, expectedDelta: Double) {
        let progress = newProgress()

        SRSEngine.processReview(progress: progress, grade: grade)

        #expect(abs(progress.easeFactor - (2.5 + expectedDelta)) < 1e-9)
    }

    @Test(arguments: [SRSEngine.Grade.again, .hard])
    func easeFactorNeverDropsBelowSM2Minimum(grade: SRSEngine.Grade) {
        let progress = newProgress()

        for _ in 0..<50 {
            SRSEngine.processReview(progress: progress, grade: grade)
            #expect(progress.easeFactor >= 1.3)
        }
        #expect(abs(progress.easeFactor - 1.3) < 1e-9)
    }

    // MARK: - Wrong answers reset

    @Test func wrongAnswerResetsIntervalAndRepetitions() {
        let progress = newProgress()
        review(progress, [.good, .good, .good, .good])
        #expect(progress.interval > 3)

        SRSEngine.processReview(progress: progress, grade: .again)

        #expect(progress.interval == 1)
        #expect(progress.repetitions == 0)
        #expect(progress.knowledgeState == .learning)
    }

    @Test func manyRepeatedFailuresStayStable() {
        let progress = newProgress()
        review(progress, Array(repeating: .good, count: 6))

        let intervals = review(progress, Array(repeating: .again, count: 100))

        #expect(intervals.allSatisfy { $0 == 1 })
        #expect(progress.repetitions == 0)
        #expect(progress.knowledgeState == .learning)
        #expect(progress.easeFactor >= 1.3)
    }

    @Test func recoveryAfterFailureRestartsTheSchedule() {
        let progress = newProgress()
        review(progress, [.good, .good, .good, .again])

        let intervals = review(progress, [.good, .good])

        #expect(intervals == [1, 3])
    }

    // MARK: - Knowledge state

    @Test func knowledgeStateProgressesWithRepetitions() {
        let progress = newProgress()

        review(progress, [.good, .good])
        #expect(progress.knowledgeState == .learning)

        review(progress, [.good])
        #expect(progress.knowledgeState == .developing)

        review(progress, [.good, .good, .good])
        #expect(progress.repetitions == 6)
        #expect(progress.knowledgeState == .mastered)
    }

    @Test func lowEaseFactorPreventsMastery() {
        let progress = newProgress()

        review(progress, Array(repeating: .hard, count: 8))

        #expect(progress.repetitions == 8)
        #expect(progress.easeFactor < 2.0)
        #expect(progress.knowledgeState == .developing)
    }

    // MARK: - Known issues

    @Test func correctAnswersGrowIntervalAtMinimumEaseFactor() {
        let progress = newProgress()
        // Failures drive the ease factor to the 1.3 floor; three Hard answers then
        // leave the interval at 1 day (1 → 2 → Int(Int(2 × 1.3) × 0.8) = 1).
        review(progress, Array(repeating: .again, count: 5))
        review(progress, Array(repeating: .hard, count: 3))
        #expect(progress.interval == 1)
        #expect(abs(progress.easeFactor - 1.3) < 1e-9)

        let intervals = review(progress, Array(repeating: .good, count: 5))

        withKnownIssue("Int(1 × 1.3) truncates to 1, so a 1-day card at the minimum ease factor never grows") {
            #expect(intervals.last! > 1, "intervals: \(intervals)")
        }
    }

    // MARK: - Due items

    @Test func dueItemsSelection() {
        let neverScheduled = UserProgress(itemID: "a", itemType: .vocabulary)
        let masteredUnscheduled = UserProgress(itemID: "b", itemType: .vocabulary, knowledgeState: .mastered)
        let overdue = UserProgress(itemID: "c", itemType: .vocabulary, nextReviewDate: Date().addingTimeInterval(-3600))
        let future = UserProgress(itemID: "d", itemType: .vocabulary, nextReviewDate: Date().addingTimeInterval(86_400))

        let due = SRSEngine.dueItems(from: [neverScheduled, masteredUnscheduled, overdue, future])

        #expect(due.map(\.itemID) == ["a", "c"])
    }
}
