import SwiftUI
import SmartPromptingCore

struct StatsView: View {
    let stats: PromptStore.UsageStats

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                overviewCards
                if !stats.topByUse.isEmpty { topUsedSection }
                if !stats.tagDistribution.isEmpty { tagSection }
                if !stats.recentlyUsed.isEmpty { recentSection }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Overview

    private var overviewCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()), GridItem(.flexible())
        ], spacing: 12) {
            StatCard(title: "Total Prompts", value: "\(stats.totalPrompts)", icon: "doc.text", color: .blue)
            StatCard(title: "Total Uses", value: "\(stats.totalUses)", icon: "arrow.counterclockwise", color: .green)
            StatCard(title: "Avg Uses", value: stats.totalPrompts > 0
                     ? String(format: "%.1f", Double(stats.totalUses) / Double(stats.totalPrompts))
                     : "0", icon: "chart.bar", color: .orange)
            StatCard(title: "Never Used", value: "\(stats.unusedCount)", icon: "moon.zzz", color: .secondary)
        }
    }

    // MARK: - Top used

    private var topUsedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Most Used", systemImage: "flame")
                .font(.headline)
                .foregroundStyle(.orange)

            ForEach(Array(stats.topByUse.enumerated()), id: \.offset) { i, item in
                HStack(spacing: 12) {
                    Text("\(i + 1)")
                        .font(.caption.weight(.bold).monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.prompt.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        UsageBar(value: item.uses, max: stats.topByUse.first?.uses ?? 1)
                    }

                    Spacer()

                    Text("\(item.uses)x")
                        .font(.subheadline.weight(.semibold).monospaced())
                        .foregroundStyle(.accentColor)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Tags

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tag Distribution", systemImage: "tag")
                .font(.headline)
                .foregroundStyle(.blue)

            FlowLayout(spacing: 8) {
                ForEach(Array(stats.tagDistribution.prefix(15).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 4) {
                        Text(item.tag)
                            .font(.caption.weight(.medium))
                        Text("\(item.count)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.08))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Recently used

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recently Used", systemImage: "clock")
                .font(.headline)
                .foregroundStyle(.green)

            ForEach(Array(stats.recentlyUsed.prefix(10).enumerated()), id: \.offset) { _, item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.prompt.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(item.prompt.slug)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(item.lastUsed, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Supporting views

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title.weight(.bold).monospaced())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct UsageBar: View {
    let value: Int
    let max: Int

    var body: some View {
        GeometryReader { geo in
            let fraction = max > 0 ? CGFloat(value) / CGFloat(max) : 0
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.accentColor.opacity(0.3))
                .frame(width: geo.size.width * fraction, height: 6)
        }
        .frame(height: 6)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), origins)
    }
}
