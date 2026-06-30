import SwiftUI
import Observation

@Observable
final class DiscoverNavigationLogger {
    static let shared = DiscoverNavigationLogger()

    private(set) var entries: [LogEntry] = []

    struct LogEntry: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let category: Category

        enum Category: String, Sendable {
            case tap
            case path
            case destination
            case data
            case error
        }
    }

    func log(_ message: String, category: LogEntry.Category) {
        let entry = LogEntry(timestamp: Date(), message: message, category: category)
        if entries.count >= 500 {
            entries.removeFirst(entries.count - 499)
        }
        entries.append(entry)
    }

    func clear() {
        entries.removeAll()
    }
}

struct DiscoverNavigationLogView: View {
    @Bindable private var logger = DiscoverNavigationLogger.shared

    var body: some View {
        List {
            ForEach(logger.entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                        Text(entry.category.rawValue.uppercased())
                            .font(.caption2)
                            .foregroundStyle(categoryColor(entry.category))
                            .fontWeight(.semibold)
                    }
                    Text(entry.message)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Navigation Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    logger.clear()
                }
                .font(.caption)
            }
        }
    }

    private func categoryColor(_ category: DiscoverNavigationLogger.LogEntry.Category) -> Color {
        switch category {
        case .tap: return .blue
        case .path: return .green
        case .destination: return .purple
        case .data: return .orange
        case .error: return .red
        }
    }
}
