import SwiftUI

struct DashboardView: View {
    @Bindable var model: DashboardViewModel

    @AppStorage("engineerMode") private var engineerMode = false

    private var cpu: CPUMetrics { model.latest?.cpu ?? .zero }
    private var memory: MemoryMetrics { model.latest?.memory ?? .zero }
    private var disk: DiskMetrics { model.latest?.disk ?? .zero }
    private var load: SystemLoad { SystemLoad.reading(model.latest) }

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
                        tint: Theme.cpu
                    )
                    MetricTileView(
                        title: "Memory",
                        value: memory.usedBytes.byteLabel,
                        caption: memoryCaption,
                        fraction: memory.usedFraction,
                        tint: Theme.memory
                    )
                    MetricTileView(
                        title: "Disk",
                        value: disk.usedFraction.percentLabel,
                        caption: diskCaption,
                        fraction: disk.usedFraction,
                        tint: Theme.disk
                    )
                }

                if engineerMode && model.canIntrospectService {
                    DashboardSection("Process Topology") {
                        ProcessTopologyView(model: model)
                    }
                }

                if engineerMode {
                    DashboardSection("Address Space") {
                        AddressSpaceView(model: model)
                    }
                }

                if engineerMode {
                    DashboardSection("Sampling Pipeline") {
                        PipelineView(timing: model.latest?.timing)
                    }
                }

                if engineerMode {
                    DashboardSection("Virtual Memory") {
                        VMCompositionView(memory: memory)
                    }
                }

                DashboardSection("CPU History") {
                    CPUHistoryChart(
                        snapshots: model.recentSnapshots,
                        capacity: model.recentSnapshots.count,
                        load: load
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
        .scrollContentBackground(.hidden)
        .toolbar { toolbarContent }
        .navigationTitle("MacEngine")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("SYSTEM ACTIVITY")
                    .font(.engineTitle)
                    .foregroundStyle(Theme.ink)
                    .kerning(1.4)
                HStack(spacing: 8) {
                    Text(load.label)
                        .font(.metricCaption)
                        .foregroundStyle(load.tint)
                        .kerning(1)
                    Text(model.latest.map { "Updated \($0.timestamp.formatted(date: .omitted, time: .standard))" }
                         ?? "Not sampling")
                        .font(.metricCaption)
                        .foregroundStyle(Theme.inkTertiary)
                }
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
                    .foregroundStyle(Theme.amber)
            }
            Spacer()
        }
        .font(.diagnosticMono)
        .foregroundStyle(Theme.inkTertiary)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $engineerMode) {
                Label("Engineer Mode", systemImage: "cpu")
            }
            .toggleStyle(.button)
            .help("Show the mechanism instead of the summary")
        }

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
        let swap = memory.swap.isActive ? " · swap \(memory.swap.usedBytes.byteLabel)" : ""
        return "of \(memory.totalBytes.byteLabel) · \(memory.pressure.rawValue)\(swap)"
    }

    private var diskCaption: String {
        guard model.latest != nil else { return "Waiting for a sample" }
        return "\(disk.volumeName) · \(disk.availableBytes.byteLabel) free"
    }
}

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
                .foregroundStyle(Theme.inkSecondary)
                .textCase(.uppercase)
                .kerning(1.2)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .panel()
    }
}
