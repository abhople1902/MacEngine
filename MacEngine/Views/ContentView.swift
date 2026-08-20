//
//  ContentView.swift
//  MacEngine
//
//  Two views onto the same monitoring service: the live dashboard, and the
//  workspace inspector that asks it a much heavier one-off question.
//

import SwiftUI

struct ContentView: View {
    @Bindable var model: DashboardViewModel
    @Bindable var inspector: WorkspaceInspectorViewModel

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
        .onAppear { model.start() }
    }
}
