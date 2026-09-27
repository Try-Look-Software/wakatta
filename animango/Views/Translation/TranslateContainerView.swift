import SwiftUI

struct TranslateContainerView: View {
    enum TranslateMode: String, CaseIterable {
        case liveTranslation = "Live"
        case wordAnalysis = "Word Analysis"
    }

    @State private var selectedMode: TranslateMode = .liveTranslation

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $selectedMode) {
                ForEach(TranslateMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch selectedMode {
            case .liveTranslation:
                LiveTranslationView()
            case .wordAnalysis:
                NavigationStack {
                    DeepWordAnalysisView()
                        .navigationTitle("Word Analysis")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }
}

#Preview {
    TranslateContainerView()
}
