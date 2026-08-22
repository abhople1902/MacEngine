//
//  AddressSpaceView.swift
//  MacEngine
//
//  The heap-and-stack diagram, drawn from live data rather than from memory.
//
//  Both processes are shown side by side because the comparison is the lesson:
//  the app carries a SwiftUI view hierarchy and the service carries a sampler,
//  and it shows in the shape of their address spaces.
//

import SwiftUI

struct AddressSpaceView: View {
    @Bindable var model: DashboardViewModel

    /// Structural data. Walking a few hundred regions twice a second would be
    /// wasteful and would tell you nothing new.
    private static let refresh: Duration = .seconds(4)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            caveat

            HStack(alignment: .top, spacing: 14) {
                process(model.appAddressSpace, fallback: "Mapping this process…")
                process(model.serviceAddressSpace, fallback: serviceFallback)
            }
        }
        .task { await pollMaps() }
    }

    private func pollMaps() async {
        while !Task.isCancelled {
            await model.refreshAddressSpaces()
            do {
                try await Task.sleep(for: Self.refresh)
            } catch {
                return
            }
        }
    }

    private var serviceFallback: String {
        model.connectionState.isStreaming
            ? "Waiting for the service to map itself"
            : "No service process to map"
    }

    /// The boundary is worth stating outright rather than leaving it as an
    /// absence someone has to notice.
    private var caveat: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock")
                .font(.system(size: 10))
                .foregroundStyle(Theme.amber)
                .padding(.top, 1)
            Text("Only these two processes. Walking another process's regions needs task_for_pid, which needs root or a debugger entitlement — so every other process on the dashboard gets footprint totals and nothing deeper.")
                .font(.metricCaption)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - One process

    @ViewBuilder
    private func process(_ map: AddressSpaceMap?, fallback: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let map {
                header(map)
                ForEach(map.significantGroups) { group in
                    row(group, virtualCeiling: map.virtualBytes)
                }
            } else {
                Text(fallback)
                    .font(.metricCaption)
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.sunk, in: .rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline, lineWidth: 1)
        }
    }

    private func header(_ map: AddressSpaceMap) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(map.processName)
                    .font(.engineBody)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 6)
                Text(verbatim: "pid \(map.processIdentifier)")
                    .font(.diagnosticMono)
                    .foregroundStyle(Theme.inkSecondary)
            }

            // The headline of the whole panel: two numbers that disagree by
            // three orders of magnitude, and only one of them is memory.
            HStack(spacing: 6) {
                Text(map.virtualBytes.byteLabel)
                    .font(.metricFigure(15))
                    .foregroundStyle(Theme.inkSecondary)
                Text("mapped")
                    .font(.metricCaption)
                    .foregroundStyle(Theme.inkTertiary)
                Text("·")
                    .foregroundStyle(Theme.inkTertiary)
                Text(map.residentBytes.byteLabel)
                    .font(.metricFigure(15))
                    .foregroundStyle(Theme.ink)
                Text("resident")
                    .font(.metricCaption)
                    .foregroundStyle(Theme.inkTertiary)
            }

            Text(verbatim: "\(map.regionCount) regions\(map.swappedBytes > 0 ? " · \(map.swappedBytes.byteLabel) swapped" : "")")
                .font(.metricCaption)
                .foregroundStyle(Theme.inkTertiary)
        }
        .padding(.bottom, 2)
    }

    private func row(_ group: RegionGroup, virtualCeiling: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(group.kind.tint)
                    .frame(width: 8, height: 8)
                Text(group.kind.title)
                    .font(.engineBody)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Text(group.residentBytes.byteLabel)
                    .font(.metricFigure(12))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 68, alignment: .trailing)
            }

            // Two bars on one baseline: the claim, and the part of it that is
            // real. Both scaled to the same ceiling so the panels compare.
            ResidencyBar(
                virtualFraction: fraction(group.virtualBytes, of: virtualCeiling),
                residentFraction: fraction(group.residentBytes, of: virtualCeiling),
                tint: group.kind.tint
            )

            Text(verbatim: "\(group.regionCount) regions · \(group.virtualBytes.byteLabel) mapped")
                .font(.metricCaption)
                .foregroundStyle(Theme.inkTertiary)
        }
        .help(group.kind.explanation)
    }

    private func fraction(_ value: UInt64, of ceiling: UInt64) -> Double {
        guard ceiling > 0 else { return 0 }
        return (Double(value) / Double(ceiling)).clampedToUnitInterval
    }
}

/// Virtual as a hairline outline, resident as the fill inside it — so a group
/// that claims a lot and uses none reads as an empty box rather than a bar.
private struct ResidencyBar: View {
    let virtualFraction: Double
    let residentFraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint.opacity(0.18))
                    .frame(width: max(proxy.size.width * virtualFraction, 2))
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: max(proxy.size.width * residentFraction, residentFraction > 0 ? 2 : 0))
            }
        }
        .frame(height: 5)
    }
}

extension RegionKind {
    var tint: Color {
        switch self {
        case .heap: Color(red: 0.663, green: 0.573, blue: 0.988)
        case .stack: Color(red: 0.937, green: 0.396, blue: 0.451)
        case .text: Color(red: 0.376, green: 0.706, blue: 0.996)
        case .mappedFile: Color(red: 0.353, green: 0.796, blue: 0.812)
        case .shared: Color(red: 0.259, green: 0.855, blue: 0.545)
        case .reserved: Color(red: 0.404, green: 0.435, blue: 0.494)
        case .other: Color(red: 0.949, green: 0.769, blue: 0.286)
        }
    }
}
