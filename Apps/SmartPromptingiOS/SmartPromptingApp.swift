import SwiftUI
import SmartPromptingCore

@main
struct SmartPromptingApp: App {
    @StateObject private var vm = LibraryViewModel()

    var body: some Scene {
        WindowGroup {
            PromptListView(vm: vm)
                .onAppear { vm.refresh() }
        }
    }
}
