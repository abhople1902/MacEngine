import SwiftUI

struct ProcessTopologyView: View {
    @Bindable var model: DashboardViewModel

    private static let refresh: Duration = .seconds(2)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                node(
                    title: "MacEngine.app",
                    role: "SwiftUI dashboard · AppKit status item",
                    pid: ProcessInfo.processInfo.processIdentifier,
                    detail: "\(model.samplesTaken) snapshots rendered",
                    tint: Theme.cpu,
                    isLive: true
                )

                link

                node(
                    title: "MonitoringService.xpc",
                    role: "launchd · on demand · samples the kernel",
                    pid: model.serviceInfo?.processIdentifier,
                    detail: peerDetail,
                    tint: Theme.disk,
                    isLive: model.serviceInfo != nil
                )
            }

            transports
        }
        .task { await pollServiceInfo() }
    }

    private func pollServiceInfo() async {
        while !Task.isCancelled {
            await model.refreshServiceInfo()
            do {
                try await Task.sleep(for: Self.refresh)
            } catch {
                return
            }
        }
    }

    private var peerDetail: String {
        guard let info = model.serviceInfo else {
            return model.connectionState.isStreaming
                ? "Not answering yet"
                : "No peer — the service is not running"
        }
        return "\(info.samplesTaken) sampled · up \(info.uptime.uptimeLabel)"
    }

    // MARK: - Nodes

    private func node(
        title: String,
        role: String,
        pid: Int32?,
        detail: String,
        tint: Color,
        isLive: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Circle()
                    .fill(isLive ? tint : Theme.inkTertiary)
                    .frame(width: 7, height: 7)
                    .shadow(color: isLive ? tint.opacity(0.8) : .clear, radius: 4)
                Text(title)
                    .font(.engineBody)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text(verbatim: pid.map { "pid \($0)" } ?? "pid —")
                    .font(.diagnosticMono)
                    .foregroundStyle(isLive ? tint : Theme.inkTertiary)
            }
            Text(role)
                .font(.metricCaption)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.metricCaption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Theme.sunk, in: .rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(isLive ? tint.opacity(0.45) : Theme.hairline, lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.35), value: isLive)
        .animation(.easeOut(duration: 0.35), value: pid)
    }

    private var link: some View {
        VStack(spacing: 3) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.connectionState.isStreaming ? Theme.green : Theme.inkTertiary)
            Text("XPC")
                .font(.metricCaption)
                .foregroundStyle(Theme.inkTertiary)
        }
        .frame(width: 42)
        .padding(.top, 14)
    }

    // MARK: - Transports

    private var transports: some View {
        VStack(spacing: 0) {
            transport(
                "NSXPCConnection",
                carries: "MetricSnapshot as JSON Data, pushed every \(model.sampleInterval.formatted(.number.precision(.fractionLength(1))))s",
                status: model.pushesReceived > 0
                    ? "\(model.pushesReceived) pushed"
                    : "no pushes yet",
                isLive: model.pushesReceived > 0
            )
            Divider().overlay(Theme.hairline)
            transport(
                "DistributedNotificationCenter",
                carries: "lifecycle events only — start, stop, lost, recovered, high CPU",
                status: "\(model.events.count) received",
                isLive: !model.events.isEmpty
            )
            Divider().overlay(Theme.hairline)
            transport(
                "Unix domain socket",
                carries: MonitoringIdentifiers.diagnosticSocketPath,
                status: model.serviceInfo?.diagnosticSocketPath == nil ? "not listening" : "listening",
                isLive: model.serviceInfo?.diagnosticSocketPath != nil
            )
        }
    }

    private func transport(_ name: String, carries: String, status: String, isLive: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(isLive ? Theme.green : Theme.inkTertiary)
                .frame(width: 5, height: 5)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.engineBody)
                    .foregroundStyle(isLive ? Theme.ink : Theme.inkSecondary)
                Text(carries)
                    .font(.metricCaption)
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(status)
                .font(.diagnosticMono)
                .foregroundStyle(isLive ? Theme.green : Theme.inkTertiary)
        }
        .padding(.vertical, 7)
    }
}
