import SwiftUI

struct ContentView: View {
    @Bindable var model: DashboardViewModel
    @Bindable var inspector: WorkspaceInspectorViewModel

    private var load: SystemLoad { SystemLoad.reading(model.latest) }

    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "gauge.with.dots.needle.33percent") {
                DashboardView(model: model)
            }
            Tab("Workspace", systemImage: "internaldrive") {
                WorkspaceInspectorView(model: inspector)
            }
        }
        .frame(minWidth: 680, minHeight: 600)
        .font(.engineBody)
        .foregroundStyle(Theme.ink)
        .tint(load.tint)
        .background(LoadWash(load: load))
        .preferredColorScheme(.dark)
        .onAppear { model.start() }
    }
}
