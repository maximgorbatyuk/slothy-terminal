import SwiftUI

/// Scrolling operational event log for the Telegram bot.
struct TelegramActivityLog: View {
  let events: [TelegramBotEvent]

  private static let timeFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss.SSS"
    return fmt
  }()

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Activity Log")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.secondary)

        Spacer()

        Text("\(events.count) events")
          .font(.system(size: 9))
          .foregroundColor(.secondary)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(appCardColor)

      Divider()

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(events) { event in
              EventRow(event: event, timeFormatter: Self.timeFormatter)
                .id(event.id)
            }
          }
          .padding(6)
        }
        .onChange(of: events.count) {
          if let lastEvent = events.last {
            withAnimation(.easeOut(duration: 0.2)) {
              proxy.scrollTo(lastEvent.id, anchor: .bottom)
            }
          }
        }
      }
    }
  }
}

/// A single event row in the activity log.
private struct EventRow: View {
  let event: TelegramBotEvent
  let timeFormatter: DateFormatter

  var body: some View {
    HStack(alignment: .top, spacing: 4) {
      Text(timeFormatter.string(from: event.timestamp))
        .font(.system(size: 9, design: .monospaced))
        .foregroundColor(.secondary)

      Text(levelIcon)
        .font(.system(size: 9))

      Text(event.message)
        .font(.system(size: 10))
        .foregroundColor(levelColor)
        .lineLimit(3)
        .textSelection(.enabled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var levelIcon: String {
    switch event.level {
    case .info:
      return "i"

    case .warning:
      return "!"

    case .error:
      return "x"
    }
  }

  private var levelColor: Color {
    switch event.level {
    case .info:
      return .secondary

    case .warning:
      return .orange

    case .error:
      return .red
    }
  }
}
