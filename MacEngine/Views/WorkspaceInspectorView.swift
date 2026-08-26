import SwiftUI

enum WorkspaceTab: String, CaseIterable, Hashable {
    case summary
    case breakdown
    case reclaimable
    case toolchain

    var dock: DockSection<WorkspaceTab> {
        switch self {
        case .summary: DockSection(tag: self, title: "Summary", symbol: "square.text.square")
        case .breakdown: DockSection(tag: self, title: "Breakdown", symbol: "list.bullet.indent")
        case .reclaimable: DockSection(tag: self, title: "Reclaimable", symbol: "trash")
        case .toolchain: DockSection(tag: self, title: "Toolchain", symbol: "hammer")
        }
    }
}

struct WorkspaceInspectorView: View {
    @Bindable var model: WorkspaceInspectorViewModel

    @State private var tab: WorkspaceTab = .summary

    var body: some View {
        VStack(spacing: 14) {
            header

            Group {
                switch model.state {
                case .idle where model.scan == nil:
                    emptyState
                case let .failed(reason):
                    failure(reason)
                default:
                    if let scan = model.scan {
                        results(scan)
                    } else {
                        emptyState
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if model.scan != nil {
                SectionDock(sections: WorkspaceTab.allCases.map(\.dock), selection: $tab, tint: Theme.memory)
            }
        }
        .padding(18)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failure(_ reason: String) -> some View {
        Label(reason, systemImage: "exclamationmark.triangle")
            .foregroundStyle(Theme.amber)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(cornerRadius: 10)
    }

    // MARK: - Tabs

    @ViewBuilder
    private func results(_ scan: WorkspaceScan) -> some View {
        switch tab {
        case .summary:
            VStack(spacing: 14) {
                totals(scan)
                DashboardSection("Scan Detail", fills: true) {
                    detail(scan)
                }
            }
        case .breakdown:
            DashboardSection("Where It Went", fills: true) {
                scrolling { breakdown(scan.sections, largest: scan.sections.map(\.node.byteCount).max() ?? 1) }
            }
        case .reclaimable:
            reclaimable(scan)
        case .toolchain:
            DashboardSection("Toolchain, Right Now", fills: true) {
                ToolchainView(footprint: scan.toolchain)
            }
        }
    }

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

    private func detail(_ scan: WorkspaceScan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            detailRow("Project", scan.workspacePath)
            Divider().overlay(Theme.hairline)
            detailRow("DerivedData", scan.derivedDataPath ?? "Not resolved — Xcode has not built this project yet")
            Divider().overlay(Theme.hairline)
            detailRow("Largest", largestLabel(scan))
            Divider().overlay(Theme.hairline)
            detailRow("Started", scan.startedAt.formatted(date: .abbreviated, time: .standard))
            Divider().overlay(Theme.hairline)
            detailRow("Walk time", "\(scan.duration.formatted(.number.precision(.fractionLength(2))))s · fts(3), \(fileCount(scan)) files")
            Spacer(minLength: 0)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.metricCaption)
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.diagnosticMono)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private func largestLabel(_ scan: WorkspaceScan) -> String {
        guard let largest = scan.sections.max(by: { $0.node.byteCount < $1.node.byteCount }) else {
            return "—"
        }
        return "\(largest.node.name) · \(largest.node.byteCount.byteLabel)"
    }

    private func fileCount(_ scan: WorkspaceScan) -> Int {
        scan.sections.reduce(0) { $0 + $1.node.fileCount }
    }

    @ViewBuilder
    private func reclaimable(_ scan: WorkspaceScan) -> some View {
        let sections = scan.sections.filter(\.isReclaimable)

        if sections.isEmpty {
            DashboardSection("Reclaimable", fills: true) {
                Text("Nothing here is safe to delete — none of the measured locations are caches or build output.")
                    .font(.metricCaption)
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(spacing: 14) {
                DashboardSection("Free Without Losing Work") {
                    HStack(alignment: .center, spacing: 16) {
                        Text(scan.reclaimableBytes.byteLabel)
                            .font(.metricFigure(30))
                            .foregroundStyle(Theme.amber)
                        Text("Caches and build output across \(sections.count) locations. Xcode regenerates every byte of it — the cost of deleting is the next build, not your work.")
                            .font(.metricCaption)
                            .foregroundStyle(Theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }

                DashboardSection("What Would Go", fills: true) {
                    scrolling { breakdown(sections, largest: sections.map(\.node.byteCount).max() ?? 1) }
                }
            }
        }
    }

    private func breakdown(_ sections: [ScanSection], largest: UInt64) -> some View {
        VStack(spacing: 0) {
            ForEach(sections) { section in
                SectionRow(
                    section: section,
                    largest: largest,
                    isExpanded: model.expanded.contains(section.node.id),
                    onToggle: { model.toggle(section.node) }
                )
                if section.id != sections.last?.id {
                    Divider()
                }
            }
        }
    }

    private func scrolling<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollContentBackground(.hidden)
        .frame(maxHeight: .infinity)
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
