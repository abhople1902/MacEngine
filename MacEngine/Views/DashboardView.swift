//
//  DashboardView.swift
//  MacEngine
//

import SwiftUI

struct DashboardView: View {
    @Bindable var model: DashboardViewModel

    private var cpu: CPUMetrics { model.latest?.cpu ?? .zero }
    private var memory: MemoryMetrics { model.latest?.memory ?? .zero }
    private var disk: DiskMetrics { model.latest?.disk ?? .zero }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                HStack(alignment: .top, spacing: 12) {
                    MetricTileView(
                        title: "CPU",
                        value: cpu.busyFraction.percentLabel,
                        caption: cpuCaption,
                        fraction: cpu.busyFraction,
                        tint: .blue
                    )
                    MetricTileView(
                        title: "Memory",
                        value: memory.usedBytes.byteLabel,
                        caption: memoryCaption,
                        fraction: memory.usedFraction,
                        tint: .purple
                    )
                    MetricTileView(
                        title: "Disk",
                        value: disk.usedFraction.percentLabel,
                        caption: diskCaption,
                        fraction: disk.usedFraction,
                        tint: .teal
                    )
                }

                DashboardSection("CPU History") {
                    CPUHistoryChart(
                        snapshots: model.recentSnapshots,
                        capacity: model.recentSnapshots.count
                    )
                }

                DashboardSection("Top Processes") {
                    ProcessListView(processes: model.latest?.topProcesses ?? [])
                }

                DashboardSection("Diagnostics") {
                    DiagnosticsView(model: model)
                }

                DashboardSection("Lifecycle Events") {
                    EventLogView(records: model.events)
                }

                footer
            }
            .padding(18)
        }
        .background(.background)
        .toolbar { toolbarContent }
        .navigationTitle("MacEngine")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("System Activity")
                    .font(.system(.title2, weight: .semibold))
                Text(model.latest.map { "Updated \($0.timestamp.formatted(date: .omitted, time: .standard))" }
                     ?? "Not sampling")
                    .font(.metricCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPillView(state: model.connectionState, source: model.source)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Label("\(model.samplesTaken) samples", systemImage: "waveform.path.ecg")
            Label("every \(model.sampleInterval.formatted(.number.precision(.fractionLength(1))))s",
                  systemImage: "timer")
            if let detail = model.connectionState.detail {
                Label(detail, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .font(.diagnosticMono)
        .foregroundStyle(.secondary)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Interval", selection: $model.sampleInterval) {
                Text("0.5s").tag(0.5)
                Text("1s").tag(1.0)
                Text("2s").tag(2.0)
                Text("5s").tag(5.0)
            }
            .pickerStyle(.menu)
            .frame(width: 80)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                model.toggle()
            } label: {
                Label(
                    model.connectionState == .idle ? "Start" : "Stop",
                    systemImage: model.connectionState == .idle ? "play.fill" : "stop.fill"
                )
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    private var cpuCaption: String {
        guard model.latest != nil else { return "Waiting for a baseline" }
        return "\(cpu.coreCount) cores · \(cpu.userFraction.percentLabel) user · \(cpu.systemFraction.percentLabel) system"
    }

    private var memoryCaption: String {
        guard model.latest != nil else { return "Waiting for a sample" }
        return "of \(memory.totalBytes.byteLabel) · \(memory.pressure.rawValue) pressure"
    }

    private var diskCaption: String {
        guard model.latest != nil else { return "Waiting for a sample" }
        return "\(disk.volumeName) · \(disk.availableBytes.byteLabel) free"
    }
}

/// Titled card used by every section of the dashboard.
struct DashboardSection<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.metricCaption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
    }
}
