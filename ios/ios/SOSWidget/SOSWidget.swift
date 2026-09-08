import SwiftUI
import WidgetKit

struct SOSEntry: TimelineEntry {
  let date: Date
}

struct SOSProvider: TimelineProvider {
  func placeholder(in context: Context) -> SOSEntry {
    SOSEntry(date: Date())
  }

  func getSnapshot(in context: Context, completion: @escaping (SOSEntry) -> Void) {
    completion(SOSEntry(date: Date()))
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<SOSEntry>) -> Void
  ) {
    completion(Timeline(entries: [SOSEntry(date: Date())], policy: .never))
  }
}

struct SOSEntryView: View {
  private let sosURL = URL(string: "medicare://sos/trigger?source=ios_widget")!
  let entry: SOSEntry

  var body: some View {
    Link(destination: sosURL) {
      VStack(spacing: 6) {
        Text("MediCare")
          .font(.caption.bold())
          .foregroundStyle(.white)

        Text("SOS")
          .font(.system(size: 32, weight: .black, design: .rounded))
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color.black.opacity(0.28))
          .clipShape(RoundedRectangle(cornerRadius: 12))
      }
      .padding(8)
    }
    .medicareWidgetBackground {
      Color(red: 0.91, green: 0.36, blue: 0.38)
    }
  }
}

@main
struct MediCareSOSWidget: Widget {
  let kind = "MediCareSOSWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: SOSProvider()) { entry in
      SOSEntryView(entry: entry)
    }
    .configurationDisplayName("MediCare SOS")
    .description("Open a cancellable SOS countdown.")
    .supportedFamilies([.systemSmall])
  }
}
