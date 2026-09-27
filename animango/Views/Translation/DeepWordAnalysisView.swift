import SwiftUI
import SwiftData

struct DeepWordAnalysisView: View {
    @State private var viewModel = DeepWordAnalysisViewModel()
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.isConfigured {
                unconfiguredView
            } else {
                inputBar

                Divider()

                if viewModel.isAnalyzing {
                    loadingView
                } else if let result = viewModel.analysisResult {
                    analysisResultView(result)
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else {
                    emptyStateView
                }
            }
        }
        .onAppear {
            viewModel.configure(modelContext: modelContext)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Enter a Japanese word...", text: $viewModel.inputText)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .submitLabel(.search)
                .onSubmit {
                    Task { await viewModel.analyzeWord() }
                }

            Button {
                isInputFocused = false
                Task { await viewModel.analyzeWord() }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.accentColor)
                    .clipShape(Circle())
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }

    // MARK: - Analysis Result

    private func analysisResultView(_ result: WordAnalysisResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                translationSection(result)
                if let conjugation = result.conjugation {
                    conjugationSection(conjugation)
                }
                if !result.kanjiBreakdown.isEmpty {
                    kanjiSection(result.kanjiBreakdown)
                }
                if !result.exampleSentences.isEmpty {
                    examplesSection(result.exampleSentences)
                }
            }
            .padding()
        }
    }

    // MARK: - Section 1: Translation & Reading

    private func translationSection(_ result: WordAnalysisResult) -> some View {
        VStack(spacing: 12) {
            // Word with furigana
            FuriganaTextView(
                text: result.inputWord,
                reading: result.reading,
                showFurigana: viewModel.showFurigana && containsKanji(result.inputWord),
                textFont: .system(size: 36, weight: .medium),
                readingFont: .title3
            )

            // Audio + Furigana toggle
            HStack(spacing: 16) {
                AudioButton(text: result.inputWord)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.showFurigana.toggle()
                    }
                } label: {
                    Image(systemName: viewModel.showFurigana ? "textformat.size" : "textformat.size.smaller")
                        .font(.body)
                        .foregroundStyle(viewModel.showFurigana ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }

            // Translation
            Text(result.translation)
                .font(.title3)
                .foregroundStyle(.primary)

            // Dictionary form (if different from input)
            if result.dictionaryForm != result.inputWord {
                HStack(spacing: 4) {
                    Text("Dictionary form:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(result.dictionaryForm)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }

            // JLPT badge + Part of speech
            HStack(spacing: 8) {
                if let level = result.jlptLevel {
                    Text("JLPT N\(level)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.jlptColor(level: level).opacity(0.2))
                        .foregroundStyle(Color.jlptColor(level: level))
                        .clipShape(Capsule())
                }

                if let pos = result.partOfSpeech {
                    Text(pos)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Section 2: Conjugation / Grammar

    private func conjugationSection(_ conjugation: ConjugationInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Grammar", systemImage: "text.book.closed")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Form:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(conjugation.currentForm)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                HStack {
                    Text("Type:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(conjugation.verbType)
                        .font(.subheadline)
                }

                Divider()

                Text("Rule")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(conjugation.ruleExplanation)
                    .font(.subheadline)

                if !conjugation.conjugationSteps.isEmpty {
                    Divider()

                    Text("Steps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(conjugation.conjugationSteps, id: \.self) { step in
                        Text(step)
                            .font(.subheadline)
                            .fontDesign(.monospaced)
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Section 3: Kanji Breakdown

    private func kanjiSection(_ kanji: [KanjiAnalysis]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Kanji", systemImage: "character.ja")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(kanji) { k in
                        kanjiCard(k)
                    }
                }
            }
        }
    }

    private func kanjiCard(_ kanji: KanjiAnalysis) -> some View {
        VStack(spacing: 8) {
            Text(kanji.character)
                .font(.system(size: 48, weight: .medium))

            Text(kanji.meanings.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if !kanji.onReadings.isEmpty {
                HStack(spacing: 4) {
                    Text("ON:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(kanji.onReadings.joined(separator: ", "))
                        .font(.caption2)
                }
            }

            if !kanji.kunReadings.isEmpty {
                HStack(spacing: 4) {
                    Text("KUN:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(kanji.kunReadings.joined(separator: ", "))
                        .font(.caption2)
                }
            }

            if let level = kanji.jlptLevel {
                Text("N\(level)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.jlptColor(level: level).opacity(0.2))
                    .foregroundStyle(Color.jlptColor(level: level))
                    .clipShape(Capsule())
            }
        }
        .frame(width: 130)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Section 4: Example Sentences

    private func examplesSection(_ examples: [AnimeExampleSentence]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Examples", systemImage: "text.quote")
                .font(.headline)

            ForEach(examples) { example in
                VStack(alignment: .leading, spacing: 6) {
                    // Japanese with furigana
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            if viewModel.showFurigana && containsKanji(example.japanese) {
                                Text(example.reading)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(example.japanese)
                                .font(.body)
                        }

                        Spacer()

                        AudioButtonCompact(text: example.japanese)
                    }

                    // English
                    Text(example.english)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Source attribution
                    Text("— \(example.source) (\(example.sourceType))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - States

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "character.magnify")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Enter a Japanese word or phrase")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Get verb forms, kanji breakdown, and example sentences from anime & manga")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Analyzing...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Try Again") {
                Task { await viewModel.analyzeWord() }
            }
            Spacer()
        }
    }

    private var unconfiguredView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("AI Provider Required")
                .font(.headline)
            Text("Set up an AI provider in Settings to use word analysis.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func containsKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }
}

#Preview {
    DeepWordAnalysisView()
        .modelContainer(for: [
            VocabularyItem.self,
            KanjiItem.self,
            LLMConfiguration.self
        ], inMemory: true)
}
