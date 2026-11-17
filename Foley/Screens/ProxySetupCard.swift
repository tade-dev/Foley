import SwiftUI

/// Shown instead of parsing when no Worker URL is configured.
struct ProxySetupCard: View {
    var onOpenDemo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.horizontal.circle").font(.system(size: 22, weight: .medium))
                Text("Connect your proxy to generate new sounds").font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            Text("Foley needs its Cloudflare Worker URL in Config/Local.xcconfig. The demo scenes work without it.")
                .font(.system(size: 15)).foregroundStyle(Theme.Colors.textSecondary).lineSpacing(3)
            HStack(spacing: 12) {
                Text("See proxy/README.md")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.bg)
                    .padding(.horizontal, 16).frame(height: 40)
                    .background(Theme.Colors.textPrimary, in: .capsule)
                    .accessibilityLabel("Setup instructions are in proxy slash README dot md")
                Button("Open a demo scene", action: onOpenDemo)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.horizontal, 16).frame(height: 40)
                    .overlay(Capsule().strokeBorder(Theme.Colors.border))
                    .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(Theme.Colors.surface, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Colors.border))
    }
}
