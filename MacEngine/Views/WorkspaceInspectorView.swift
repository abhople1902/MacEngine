import SwiftUI

struct WorkspaceInspectorView: View {
    @Bindable var model: WorkspaceInspectorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                switch model.state {
                case .idle where model.scan == nil:
                    emptyState
                case let .failed(reason):
                    failure(reason)
                default:
                    if let scan = model.scan {
                        totals(scan)
                        DashboardSection("Where it went") {
                            breakdown(scan)
                        }
                        DashboardSection("Toolchain, right now") {
                            ToolchainView(footprint: scan.toolchain)
                        }
                    } else {
                        emptyState
                    }
                }
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Workspace")
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.workspaceName ?? "No project chosen")
                    .font(.engineTitle)
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.metricCaption)
                    .foregroundStyle(Theme.inkTertiary)
            }
            Spacer()
            if model.state.isScanning {
                Button("Cancel", systemImage: "stop.circle") { model.cancel() }
            } else {
                Button("Choose Project…", systemImage: "folder") { model.chooseWorkspace() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canScan)
            }
        }
    }

    private var subtitle: String {
        switch model.state {
        case let .scanning(location, completed, total):
            total > 1 ? "Measuring \(location) — \(completed) of \(total)" : "Measuring \(location)"
        case .failed:
            "Scan failed"
        case .idle, .finished:
            model.scan.map {
                "Measured in \($0.duration.formatted(.number.precision(.fractionLength(1))))s · \($0.sections.count) locations"
            } ?? "Measured by the monitoring service, not by this app"
        }
    }

    // MARK: - States

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing measured yet", systemImage: "internaldrive")
        } description: {
            Text(model.canScan
                 ? "Choose an .xcodeproj or .xcworkspace. The service resolves its DerivedData folder and measures everything Xcode keeps for it."
                 : "The in-process provider cannot scan. Run against the monitoring service.")
        } actions: {
            if model.canScan {
                Button("Choose Project…") { model.chooseWorkspace() }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private func failure(_ reason: String) -> some View {
        Label(reason, systemImage: "exclamationmark.triangle")
            .foregroundStyle(Theme.amber)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(cornerRadius: 10)
    }

    // MARK: - Results

    private func totals(_ scan: WorkspaceScan) -> some View {
        HStack(alignment: .top, spacing: 12) {
            MetricTileView(
                title: "Total",
                value: scan.totalBytes.byteLabel,
                caption: "across \(scan.sections.count) locations",
                fraction: 1,
                tint: Theme.memory
            )
            MetricTileView(
                title: "Reclaimable",
                value: scan.reclaimableBytes.byteLabel,
                caption: "caches and build output",
                fraction: scan.totalBytes > 0 ? Double(scan.reclaimableBytes) / Double(scan.totalBytes) : 0,
                tint: Theme.amber
            )
            MetricTileView(
                title: "Toolchain",
                value: scan.toolchain.totalBytes.byteLabel,
                caption: "\(scan.toolchain.processCount) live processes",
                fraction: 0,
                tint: Theme.disk
            )
        }
    }

    private func breakdown(_ scan: WorkspaceScan) -> some View {
        let largest = scan.sections.map(\.node.byteCount).max() ?? 1

        return VStack(spacing: 0) {
            ForEach(scan.sections) { section in
                SectionRow(
                    section: section,
                    largest: largest,
                    isExpanded: model.expanded.contains(section.node.id),
                    onToggle: { model.toggle(section.node) }
                )
                if section.id != scan.sections.last?.id {
                    Divider()
                }
            }
        }
    }
}

private struct SectionRow: View {
    let section: ScanSection
    let largest: UInt64
    let isExpanded: Bool
    let onToggle: () -> Void

    private var hasChildren: Bool { !section.node.children.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: hasChildren ? "chevron.right" : "circle.fill")
                        .font(.system(size: hasChildren ? 10 : 4, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .rotationEffect(.degrees(isExpanded && hasChildren ? 90 : 0))
                        .frame(width: 12)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(section.node.name)
                            .font(.engineBody)
                            .foregroundStyle(Theme.ink)
                        Text(section.isAbsent ? "Not present on this Mac" : section.note)
                            .font(.metricCaption)
                            .foregroundStyle(Theme.inkTertiary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 12)

                    if section.isReclaimable && section.node.byteCount > 0 {
                        Text("reclaimable")
                            .font(.metricCaption)
                            .foregroundStyle(Theme.amber)
                    }

                    Text(section.node.byteCount.byteLabel)
                        .font(.metricFigure(14))
                        .frame(width: 78, alignment: .trailing)
                }
            }
            .buttonStyle(.plain)
            .disabled(!hasChildren)

            ProportionBar(
                fraction: largest > 0 ? Double(section.node.byteCount) / Double(largest) : 0,
                isReclaimable: section.isReclaimable
            )

            if isExpanded {
                VStack(spacing: 3) {
                    ForEach(section.node.children.prefix(8)) { child in
                        HStack(spacing: 8) {
                            Text(child.name)
                                .font(.diagnosticMono)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text("\(child.fileCount) files")
                                .font(.metricCaption)
                                .foregroundStyle(Theme.inkTertiary)
                            Text(child.byteCount.byteLabel)
                                .font(.diagnosticMono)
                                .frame(width: 70, alignment: .trailing)
                        }
                    }
                    if section.node.children.count > 8 {
                        HStack {
                            Text("+ \(section.node.children.count - 8) more")
                                .font(.metricCaption)
                                .foregroundStyle(Theme.inkTertiary)
                            Spacer()
                        }
                    }
                }
                .padding(.leading, 22)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 9)
    }
}

private struct ProportionBar: View {
    let fraction: Double
    let isReclaimable: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.sunk)
                Capsule()
                    .fill(isReclaimable ? Theme.amber.gradient : Theme.memory.gradient)
                    .frame(width: max(geometry.size.width * fraction, fraction > 0 ? 3 : 0))
            }
        }
        .frame(height: 4)
        .padding(.leading, 22)
    }
}

private struct ToolchainView: View {
    let footprint: ToolchainFootprint

    var body: some View {
        if footprint.groups.isEmpty {
            Text("No toolchain processes running. Open Xcode and scan again.")
                .font(.metricCaption)
                .foregroundStyle(Theme.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 4) {
                ForEach(footprint.groups) { group in
                    HStack(spacing: 10) {
                        Text(group.name)
                            .font(.engineBody)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        if group.processCount > 1 {
                            Text("×\(group.processCount)")
                                .font(.diagnosticMono)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer(minLength: 12)
                        Text(group.cpuFraction.precisePercentLabel)
                            .font(.diagnosticMono)
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(width: 58, alignment: .trailing)
                        Text(group.memoryBytes.byteLabel)
                            .font(.metricFigure(14))
                            .frame(width: 78, alignment: .trailing)
                    }
                }
            }
        }
    }
}
