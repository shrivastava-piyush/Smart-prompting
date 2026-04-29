import SwiftUI
import SmartPromptingCore

@main
struct SmartPromptingApp: App {
    @StateObject private var vm = LibraryViewModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                PromptListView(vm: vm)
                    .onAppear { vm.refresh() }
                    .tabItem {
                        Label("Prompts", systemImage: "text.bubble")
                    }

                NavigationStack {
                    if let stats = vm.usageStats {
                        StatsView(stats: stats)
                    } else {
                        ProgressView("Loading...")
                    }
                }
                .onAppear { vm.loadStats() }
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar")
                }
            }
        }
    }
}
