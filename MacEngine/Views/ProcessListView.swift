//
//  ProcessListView.swift
//  MacEngine
//
//  Rows arrive from the monitoring service. The app deliberately does not
//  enumerate processes itself: that work belongs in the isolated process, and
//  the App Sandbox on this target would block most of it anyway.
//

import SwiftUI

struct ProcessListView: View {
    let processes: [ProcessSample]

    var body: some View {
        if processes.isEmpty {
            ContentUnavailableView {
                Label("No process data", systemImage: "list.bullet.rectangle")
            } description: {
                Text("Process enumeration runs inside the monitoring service.")
                    .font(.metricCaption)
            }
            .frame(height: 130)
        } else {
            Table(processes) {
                TableColumn("Process") { Text($0.name).lineLimit(1) }
                TableColumn("PID") { Text(String($0.pid)).font(.diagnosticMono) }
                    .width(60)
                TableColumn("CPU") { Text($0.cpuFraction.precisePercentLabel).font(.diagnosticMono) }
                    .width(70)
                TableColumn("Memory") { Text($0.memoryBytes.byteLabel).font(.diagnosticMono) }
                    .width(90)
            }
            .frame(height: 180)
        }
    }
}
