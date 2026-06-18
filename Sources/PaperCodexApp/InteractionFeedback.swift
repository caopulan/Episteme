import PaperCodexCore
import SwiftUI

enum InteractionNoticeKind: Equatable {
    case success
    case info
    case warning
    case error

    var systemImage: String {
        switch self {
        case .success:
            "checkmark.circle.fill"
        case .info:
            "info.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .error:
            "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .success:
            .green
        case .info:
            .blue
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}

func defaultNoticeDismissDuration(for kind: InteractionNoticeKind) -> TimeInterval {
    switch kind {
    case .success:
        5
    case .error:
        10
    case .warning:
        10
    case .info:
        5
    }
}

struct InteractionNotice: Identifiable, Equatable {
    var id = UUID()
    var kind: InteractionNoticeKind
    var title: String
    var message: String
    var createdAt = Date()
    var autoDismissAfter: TimeInterval? = 5
}

struct AppOperationStatus: Equatable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var systemImage: String
    var tint: Color
    var fraction: Double? = nil

    init(
        id: String,
        title: String,
        detail: String,
        systemImage: String,
        tint: Color,
        fraction: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.tint = tint
        self.fraction = fraction
    }
}

struct CacheStorageSummary: Equatable, Sendable {
    var libraryBytes: Int64 = 0
    var disposableCacheBytes: Int64 = 0
    var arxivCacheBytes: Int64 = 0
    var thumbnailBytes: Int64 = 0
    var refreshedAt: Date?

    var totalCacheBytes: Int64 {
        disposableCacheBytes + arxivCacheBytes + thumbnailBytes
    }

    var detailText: String {
        "Library \(Self.formatBytes(libraryBytes)) · Cache \(Self.formatBytes(totalCacheBytes))"
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct CitationReturnPoint: Equatable {
    var paperID: String
    var paperTitle: String
    var position: PaperReaderPosition
    var label: String
}

struct PDFInternalLinkTarget: Equatable {
    var pageIndex: Int
    var pagePointX: Double
    var pagePointY: Double
}

enum PDFKitCommandKind: Equatable {
    case zoomIn
    case zoomOut
    case fitWidth
    case fitPage
    case previousPage
    case nextPage
    case restorePosition(PaperReaderPosition)
}

struct PDFKitCommand: Identifiable, Equatable {
    var id = UUID()
    var kind: PDFKitCommandKind
}

struct PDFDocumentStatus: Equatable {
    var pageIndex: Int
    var pageCount: Int
    var scaleFactor: Double
}

enum DiscoverPaperInteractionState: Equatable {
    case queued
    case processing
    case processed
    case cached
    case failed
    case cancelled
    case downloading
    case pdfCached
}

struct InteractionNoticeStack: View {
    var notices: [InteractionNotice]
    var onDismiss: (InteractionNotice.ID) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(notices) { notice in
                InteractionNoticeCard(notice: notice) {
                    onDismiss(notice.id)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(14)
        .frame(maxWidth: 560, alignment: .topTrailing)
        .animation(.spring(response: 0.22, dampingFraction: 0.86), value: notices)
    }
}

private struct InteractionNoticeCard: View {
    var notice: InteractionNotice
    var onDismiss: () -> Void

    @State private var isExpanded = false

    private var canExpand: Bool {
        notice.message.count > 180 || notice.message.contains("\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: notice.kind.systemImage)
                    .foregroundStyle(notice.kind.tint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(notice.title)
                        .font(.paperCodexSystem(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if !notice.message.isEmpty, !isExpanded {
                        Text(notice.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 8)
                if canExpand {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Label(isExpanded ? "Less" : "Details", systemImage: isExpanded ? "chevron.up" : "doc.text.magnifyingglass")
                            .labelStyle(.iconOnly)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(isExpanded ? "Hide details" : "Show details")
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.paperCodexSystem(size: 10, weight: .bold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss notification")
            }
            if isExpanded, !notice.message.isEmpty {
                ScrollView(.vertical) {
                    Text(notice.message)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(notice.kind.tint.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 12, y: 6)
    }
}

struct GlobalOperationStatusView: View {
    var status: AppOperationStatus

    var body: some View {
        GlobalOperationStackView(statuses: [status])
    }
}

struct GlobalOperationStackView: View {
    var statuses: [AppOperationStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: statuses.count > 1 ? 10 : 0) {
            ForEach(statuses) { status in
                GlobalOperationStatusRow(status: status, isCompact: statuses.count > 1)
            }
        }
        .padding(.horizontal, statuses.count > 1 ? 14 : 18)
        .padding(.vertical, statuses.count > 1 ? 10 : 12)
        .frame(width: statuses.count > 1 ? 360 : 340, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderTint.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 14, y: 7)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var borderTint: Color {
        statuses.first?.tint ?? .accentColor
    }

    private var accessibilitySummary: String {
        statuses.map { "\($0.title). \($0.detail)" }.joined(separator: ". ")
    }
}

private struct GlobalOperationStatusRow: View {
    var status: AppOperationStatus
    var isCompact: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.systemImage)
                .font(.paperCodexSystem(size: isCompact ? 14 : 16, weight: .semibold))
                .foregroundStyle(status.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: isCompact ? 3 : 6) {
                HStack(spacing: 8) {
                    Text(status.title)
                        .font(.paperCodexSystem(size: isCompact ? 12.5 : 13.5, weight: .semibold))
                        .lineLimit(1)
                    Text(status.detail)
                        .font(.paperCodexSystem(size: isCompact ? 11.5 : 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let fraction = status.fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(status.tint)
                        .frame(height: 4)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .tint(status.tint)
                        .frame(height: 4)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.title). \(status.detail)")
    }
}
