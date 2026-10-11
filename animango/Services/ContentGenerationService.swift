import Foundation
import SwiftData

@Observable @MainActor
final class ContentGenerationService {
    private let jishoService = JishoService()
    private let animangoAPI = AnimangoAPIService()
    let llmManager = LLMServiceManager()

    var isGenerating = false
    var generationProgress: String = ""
    var errorMessage: String?

    var isAIAvailable: Bool {
        llmManager.isAvailable
    }

    var aiUnavailableReason: String? {
        llmManager.unavailableReason
    }

    func generateContentForEpisode(
        episode: Episode,
        media: Media,
        modelContext: ModelContext
    ) async {
        isGenerating = true
        errorMessage = nil

        // Ensure LLM is configured
        llmManager.loadConfiguration(modelContext: modelContext)

        do {
            // Tier 1: Try cloud API (Animango backend)
            generationProgress = "Checking cloud data..."
            if let cloudContent = try? await animangoAPI.fetchEpisodeContent(
                mediaID: media.externalID,
                episodeNumber: episode.episodeNumber
            ) {
                generationProgress = "Loading cloud data..."
                persistCloudContent(
                    cloudContent,
                    episodeID: episode.id,
                    mediaExternalID: media.externalID,
                    modelContext: modelContext
                )
                generationProgress = "Done!"
                try modelContext.save()
                isGenerating = false
                return
            }

            // Tier 2: Jisho + LLM generation
            // Step 1: Look up vocabulary from Jisho
            generationProgress = "Looking up vocabulary..."
            let jishoWords = try await fetchJishoVocabulary(for: media.title)

            // Step 2: Persist Jisho vocabulary
            generationProgress = "Saving vocabulary..."
            persistJishoVocabulary(
                jishoWords,
                episodeID: episode.id,
                mediaExternalID: media.externalID,
                modelContext: modelContext
            )

            // Step 3: Generate lessons with configured LLM
            if llmManager.isAvailable {
                generationProgress = "Generating lessons with \(llmManager.currentProvider.displayName)..."
                let content = try await llmManager.generateEpisodeContent(
                    mediaTitle: media.title,
                    episodeTitle: episode.title,
                    episodeNumber: episode.episodeNumber,
                    mediaType: media.mediaType.displayName
                )

                // Step 4: Persist generated content
                generationProgress = "Saving lessons..."
                persistGeneratedContent(
                    content,
                    episodeID: episode.id,
                    mediaExternalID: media.externalID,
                    modelContext: modelContext
                )
            } else {
                // Tier 3: Jisho-only fallback lessons
                generationProgress = "Creating lessons from vocabulary..."
                createFallbackLessons(from: jishoWords, episodeID: episode.id, modelContext: modelContext)
            }

            generationProgress = "Done!"
            try modelContext.save()
        } catch {
            errorMessage = "Failed to generate content: \(error.localizedDescription)"
        }

        isGenerating = false
    }

    // MARK: - Jisho Vocabulary Fetch

    private func fetchJishoVocabulary(for title: String) async throws -> [JishoService.JishoWord] {
        let words = try await jishoService.searchWords(keyword: title)
        return Array(words.prefix(12))
    }

    // MARK: - Persist Jisho Vocabulary

    private func persistJishoVocabulary(
        _ words: [JishoService.JishoWord],
        episodeID: String,
        mediaExternalID: String,
        modelContext: ModelContext
    ) {
        for jishoWord in words {
            let data = jishoService.toVocabularyData(jishoWord)

            let word = data.word
            let existingPredicate = #Predicate<VocabularyItem> { $0.word == word }
            let existing = try? modelContext.fetch(FetchDescriptor(predicate: existingPredicate))

            if existing?.isEmpty ?? true {
                let vocabItem = VocabularyItem(
                    word: data.word,
                    reading: data.reading,
                    meaning: data.meaning,
                    jlptLevel: data.jlpt,
                    partOfSpeech: data.partOfSpeech
                )
                modelContext.insert(vocabItem)
            }

            let epID = episodeID
            let linkPredicate = #Predicate<EpisodeVocabulary> {
                $0.episodeID == epID && $0.vocabularyWord == word
            }
            let existingLink = try? modelContext.fetch(FetchDescriptor(predicate: linkPredicate))

            if existingLink?.isEmpty ?? true {
                let link = EpisodeVocabulary(
                    episodeID: episodeID,
                    vocabularyWord: data.word,
                    frequency: 1
                )
                modelContext.insert(link)
            }

            linkVocabularyToMedia(word: data.word, mediaExternalID: mediaExternalID, modelContext: modelContext)
        }
    }

    private func linkVocabularyToMedia(word: String, mediaExternalID: String, modelContext: ModelContext) {
        let mediaID = mediaExternalID
        let predicate = #Predicate<MediaVocabulary> {
            $0.mediaExternalID == mediaID && $0.vocabularyWord == word
        }
        if (try? modelContext.fetch(FetchDescriptor(predicate: predicate)))?.isEmpty ?? true {
            modelContext.insert(MediaVocabulary(
                mediaExternalID: mediaExternalID,
                vocabularyWord: word,
                frequency: 1
            ))
        }
    }

    // MARK: - Persist Generated Content

    private func persistGeneratedContent(
        _ content: LLMGeneratedContent,
        episodeID: String,
        mediaExternalID: String,
        modelContext: ModelContext
    ) {
        // Persist additional vocabulary from AI generation
        for vocabItem in content.vocabulary {
            let word = vocabItem.word
            let existingPredicate = #Predicate<VocabularyItem> { $0.word == word }
            let existing = try? modelContext.fetch(FetchDescriptor(predicate: existingPredicate))

            if existing?.isEmpty ?? true {
                let item = VocabularyItem(
                    word: vocabItem.word,
                    reading: vocabItem.reading,
                    meaning: vocabItem.meaning
                )
                modelContext.insert(item)
            }

            let epID = episodeID
            let linkPredicate = #Predicate<EpisodeVocabulary> {
                $0.episodeID == epID && $0.vocabularyWord == word
            }
            let existingLink = try? modelContext.fetch(FetchDescriptor(predicate: linkPredicate))

            if existingLink?.isEmpty ?? true {
                let link = EpisodeVocabulary(
                    episodeID: episodeID,
                    vocabularyWord: vocabItem.word,
                    frequency: 1
                )
                modelContext.insert(link)
            }

            linkVocabularyToMedia(word: vocabItem.word, mediaExternalID: mediaExternalID, modelContext: modelContext)
        }

        // Persist lessons and exercises
        for (lessonIndex, generatedLesson) in content.lessons.enumerated() {
            let lessonID = "\(episodeID)_generated_lesson_\(lessonIndex + 1)"

            // Persist grammar point if it doesn't exist
            let pattern = generatedLesson.grammarPattern
            let grammarPredicate = #Predicate<GrammarPoint> { $0.pattern == pattern }
            let existingGrammar = try? modelContext.fetch(FetchDescriptor(predicate: grammarPredicate))

            if existingGrammar?.isEmpty ?? true {
                let examples = generatedLesson.examples.map {
                    GrammarExample(japanese: $0.japanese, reading: $0.reading, english: $0.english)
                }
                let grammarPoint = GrammarPoint(
                    pattern: generatedLesson.grammarPattern,
                    explanation: generatedLesson.explanation,
                    examples: examples
                )
                modelContext.insert(grammarPoint)
            }

            // Create episode-grammar link
            let epID = episodeID
            let grammarLinkPredicate = #Predicate<EpisodeGrammar> {
                $0.episodeID == epID && $0.grammarPattern == pattern
            }
            let existingGrammarLink = try? modelContext.fetch(FetchDescriptor(predicate: grammarLinkPredicate))

            if existingGrammarLink?.isEmpty ?? true {
                let grammarLink = EpisodeGrammar(
                    episodeID: episodeID,
                    grammarPattern: generatedLesson.grammarPattern
                )
                modelContext.insert(grammarLink)
            }

            // Media link (the media Grammar list reads these)
            let mediaID = mediaExternalID
            let mediaGrammarPredicate = #Predicate<MediaGrammar> {
                $0.mediaExternalID == mediaID && $0.grammarPattern == pattern
            }
            if (try? modelContext.fetch(FetchDescriptor(predicate: mediaGrammarPredicate)))?.isEmpty ?? true {
                modelContext.insert(MediaGrammar(
                    mediaExternalID: mediaExternalID,
                    grammarPattern: generatedLesson.grammarPattern
                ))
            }

            // Create lesson
            let lesson = Lesson(
                id: lessonID,
                episodeID: episodeID,
                grammarPattern: generatedLesson.grammarPattern,
                title: generatedLesson.title,
                order: lessonIndex + 1
            )
            modelContext.insert(lesson)

            // Create exercises
            for (exerciseIndex, generatedExercise) in generatedLesson.exercises.enumerated() {
                let exerciseID = "\(lessonID)_ex_\(exerciseIndex + 1)"
                let exerciseType = mapExerciseType(generatedExercise.exerciseType)

                let exercise = LessonExercise(
                    id: exerciseID,
                    lessonID: lessonID,
                    exerciseType: exerciseType,
                    prompt: generatedExercise.prompt,
                    answer: generatedExercise.answer,
                    hint: generatedExercise.hint,
                    order: exerciseIndex + 1
                )
                modelContext.insert(exercise)
            }
        }
    }

    // MARK: - Fallback Lesson Creation

    private func createFallbackLessons(
        from words: [JishoService.JishoWord],
        episodeID: String,
        modelContext: ModelContext
    ) {
        guard !words.isEmpty else { return }

        let lessonID = "\(episodeID)_fallback_lesson_1"
        let lesson = Lesson(
            id: lessonID,
            episodeID: episodeID,
            grammarPattern: "Vocabulary Review",
            title: "Vocabulary Practice",
            order: 1
        )
        modelContext.insert(lesson)

        for (index, word) in words.prefix(6).enumerated() {
            let data = jishoService.toVocabularyData(word)
            let exerciseID = "\(lessonID)_ex_\(index + 1)"

            let exercise = LessonExercise(
                id: exerciseID,
                lessonID: lessonID,
                exerciseType: .vocabRecall,
                prompt: "What is the meaning of \(data.word) (\(data.reading))?",
                answer: data.meaning,
                hint: "Think about the reading: \(data.reading)",
                order: index + 1
            )
            modelContext.insert(exercise)
        }
    }

    // MARK: - Persist Cloud Content

    private func persistCloudContent(
        _ content: AnimangoAPIService.EpisodeContentDTO,
        episodeID: String,
        mediaExternalID: String,
        modelContext: ModelContext
    ) {
        // Persist vocabulary
        for vocab in content.vocabulary {
            let word = vocab.word
            let existingPredicate = #Predicate<VocabularyItem> { $0.word == word }
            let existing = try? modelContext.fetch(FetchDescriptor(predicate: existingPredicate))

            if existing?.isEmpty ?? true {
                let item = VocabularyItem(
                    word: vocab.word,
                    reading: vocab.reading ?? "",
                    meaning: vocab.meaning ?? "",
                    jlptLevel: vocab.jlptLevel,
                    frequency: vocab.frequency,
                    partOfSpeech: vocab.partOfSpeech,
                    exampleSentenceJP: vocab.exampleSentenceJp,
                    exampleSentenceEN: vocab.exampleSentenceEn
                )
                modelContext.insert(item)
            }

            // Episode link
            let epID = episodeID
            let linkPredicate = #Predicate<EpisodeVocabulary> {
                $0.episodeID == epID && $0.vocabularyWord == word
            }
            if (try? modelContext.fetch(FetchDescriptor(predicate: linkPredicate)))?.isEmpty ?? true {
                modelContext.insert(EpisodeVocabulary(
                    episodeID: episodeID,
                    vocabularyWord: vocab.word,
                    frequency: vocab.episodeFrequency ?? 1
                ))
            }

            // Media link
            let mediaID = mediaExternalID
            let mediaLinkPredicate = #Predicate<MediaVocabulary> {
                $0.mediaExternalID == mediaID && $0.vocabularyWord == word
            }
            if (try? modelContext.fetch(FetchDescriptor(predicate: mediaLinkPredicate)))?.isEmpty ?? true {
                modelContext.insert(MediaVocabulary(
                    mediaExternalID: mediaExternalID,
                    vocabularyWord: vocab.word,
                    frequency: vocab.episodeFrequency ?? 1
                ))
            }
        }

        // Persist kanji
        for kanjiDTO in content.kanji {
            let char = kanjiDTO.character
            let existingPredicate = #Predicate<KanjiItem> { $0.character == char }
            let existing = try? modelContext.fetch(FetchDescriptor(predicate: existingPredicate))

            if existing?.isEmpty ?? true {
                let item = KanjiItem(
                    character: kanjiDTO.character,
                    onReadings: kanjiDTO.onReadings,
                    kunReadings: kanjiDTO.kunReadings,
                    meaning: kanjiDTO.meaning ?? "",
                    strokeCount: kanjiDTO.strokeCount ?? 0,
                    jlptLevel: kanjiDTO.jlptLevel,
                    grade: kanjiDTO.grade
                )
                modelContext.insert(item)
            }

            // Episode link
            let epID = episodeID
            let linkPredicate = #Predicate<EpisodeKanji> {
                $0.episodeID == epID && $0.kanjiCharacter == char
            }
            if (try? modelContext.fetch(FetchDescriptor(predicate: linkPredicate)))?.isEmpty ?? true {
                modelContext.insert(EpisodeKanji(
                    episodeID: episodeID,
                    kanjiCharacter: kanjiDTO.character
                ))
            }

            // Media link
            let mediaID = mediaExternalID
            let mediaLinkPredicate = #Predicate<MediaKanji> {
                $0.mediaExternalID == mediaID && $0.kanjiCharacter == char
            }
            if (try? modelContext.fetch(FetchDescriptor(predicate: mediaLinkPredicate)))?.isEmpty ?? true {
                modelContext.insert(MediaKanji(
                    mediaExternalID: mediaExternalID,
                    kanjiCharacter: kanjiDTO.character
                ))
            }
        }

        // Persist grammar
        for grammarDTO in content.grammar {
            let pattern = grammarDTO.pattern
            let existingPredicate = #Predicate<GrammarPoint> { $0.pattern == pattern }
            let existing = try? modelContext.fetch(FetchDescriptor(predicate: existingPredicate))

            if existing?.isEmpty ?? true {
                let examples = grammarDTO.examples.map {
                    GrammarExample(
                        japanese: $0.japanese,
                        reading: $0.reading ?? "",
                        english: $0.english ?? ""
                    )
                }
                let grammarPoint = GrammarPoint(
                    pattern: grammarDTO.pattern,
                    explanation: grammarDTO.explanation ?? "",
                    jlptLevel: grammarDTO.jlptLevel,
                    examples: examples
                )
                modelContext.insert(grammarPoint)
            }

            // Episode link
            let epID = episodeID
            let grammarLinkPredicate = #Predicate<EpisodeGrammar> {
                $0.episodeID == epID && $0.grammarPattern == pattern
            }
            if (try? modelContext.fetch(FetchDescriptor(predicate: grammarLinkPredicate)))?.isEmpty ?? true {
                modelContext.insert(EpisodeGrammar(
                    episodeID: episodeID,
                    grammarPattern: grammarDTO.pattern
                ))
            }

            // Media link
            let mediaID = mediaExternalID
            let mediaGrammarLinkPredicate = #Predicate<MediaGrammar> {
                $0.mediaExternalID == mediaID && $0.grammarPattern == pattern
            }
            if (try? modelContext.fetch(FetchDescriptor(predicate: mediaGrammarLinkPredicate)))?.isEmpty ?? true {
                modelContext.insert(MediaGrammar(
                    mediaExternalID: mediaExternalID,
                    grammarPattern: grammarDTO.pattern
                ))
            }
        }
    }

    // MARK: - Helpers

    private func mapExerciseType(_ typeString: String) -> ExerciseType {
        switch typeString {
        case "vocabRecall": return .vocabRecall
        case "kanjiReading": return .kanjiReading
        case "grammarFill": return .grammarFill
        case "translation": return .translation
        case "pronunciation": return .pronunciation
        default: return .vocabRecall
        }
    }
}
