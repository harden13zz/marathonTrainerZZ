import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("今日", systemImage: "figure.run") }

            HistoryView()
                .tabItem { Label("历史", systemImage: "chart.bar") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}

#if DEBUG
#Preview {
    ContentView()
        .modelContainer(for: [
            UserProfileRecord.self, TrainingSessionRecord.self, TrainingLogRecord.self,
            DailyRecoveryRecord.self, DailyWeatherRecord.self, TrainingPlanRecord.self, AppNoteRecord.self
        ], inMemory: true)
}
#endif
