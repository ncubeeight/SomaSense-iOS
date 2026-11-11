import SwiftUI

@main
struct SomaSenseApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .onChange(of: phase) { _, p in if p == .active { model.rollDate() } }
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let hideBar = (model.tab == .home && !model.selected.isEmpty) || model.composing
        TabView(selection: Binding(get: { model.tab }, set: { model.pick($0) })) {
            Tab("Body map", systemImage: "figure.stand", value: AppModel.Tab.home) {
                HomeView().toolbar(hideBar ? .hidden : .visible, for: .tabBar)
            }
            Tab("Calendar", systemImage: "calendar", value: AppModel.Tab.calendar) { CalendarView() }
            Tab("Reports", systemImage: "chart.bar", value: AppModel.Tab.reports) { ReportsView() }
            Tab("Settings", systemImage: "slider.horizontal.3", value: AppModel.Tab.settings) { SettingsView() }
        }
        .tint(Ink.teal)
        .fullScreenCover(isPresented: $model.composing) { ComposeView().environment(model) }
        .sheet(isPresented: Binding(get: { model.detailId != nil && model.detailReport != nil }, set: { if !$0 { model.detailId = nil } })) {
            if let r = model.detailReport { DetailView(report: r).environment(model) }
        }
        .overlay(alignment: .bottom) {
            if let t = model.toast {
                Text(t)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Ink.text, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20).padding(.bottom, 100)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        .onChange(of: model.toast) { _, t in
            if let t { AccessibilityNotification.Announcement(t).post() }
        }
    }
}
