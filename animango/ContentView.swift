import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            Tab("Discover", systemImage: "sparkles") {
                DiscoverView()
            }

            Tab("Library", systemImage: "books.vertical") {
                LibraryView()
            }

            Tab("Study", systemImage: "brain.head.profile") {
                StudyView()
            }

            Tab("Chat", systemImage: "bubble.left.and.bubble.right") {
                ChatConversationListView()
            }

            Tab("Translate", systemImage: "waveform.and.mic") {
                TranslateContainerView()
            }

            Tab("Profile", systemImage: "person.crop.circle") {
                ProfileView()
            }
        }
        .task {
            SampleData.loadIfNeeded(modelContext: modelContext)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            Media.self,
            VocabularyItem.self,
            KanjiItem.self,
            GrammarPoint.self,
            UserProgress.self,
            MediaVocabulary.self,
            MediaKanji.self,
            MediaGrammar.self,
            Episode.self,
            EpisodeVocabulary.self,
            EpisodeKanji.self,
            EpisodeGrammar.self,
            Lesson.self,
            LessonExercise.self,
            ChatConversation.self,
            ChatMessageData.self
        ], inMemory: true)
}
