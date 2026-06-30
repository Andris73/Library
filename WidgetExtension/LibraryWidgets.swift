import SwiftUI
import WidgetKit

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: Date())], policy: .atEnd))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct LibraryWidgetsEntryView: View {
    var entry: SimpleEntry

    var body: some View {
        Text("Library")
    }
}

struct LibraryWidgets: Widget {
    let kind: String = "LibraryWidgets"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            LibraryWidgetsEntryView(entry: entry)
        }
        .configurationDisplayName("Library")
        .description("Quick access to your library.")
    }
}
