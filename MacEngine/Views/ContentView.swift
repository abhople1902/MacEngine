//
//  ContentView.swift
//  MacEngine
//
//  Two views onto the same monitoring service: the live dashboard, and the
//  workspace inspector that asks it a much heavier one-off question.
//
//  Both sit on one shared background, so the corner wash tracks the machine
//  across the whole window rather than restarting per tab.
//

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
        // The palette is the app's, not the system's: MacEngine reads the same
        // whatever the Mac is set to.
        .preferredColorScheme(.dark)
        .onAppear { model.start() }
    }
}
