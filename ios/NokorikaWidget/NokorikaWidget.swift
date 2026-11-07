import SwiftUI
import WidgetKit

private let widgetGroupId = "group.com.nokorikastudio.nokorika"

private enum WidgetKeys {
  static let remainingByDate = "remaining_by_date"
  static let lastBusinessDay = "last_business_day"
  static let monthLabel = "month_label"
  static let monthKey = "month_key"
  static let totalBusinessDays = "total_business_days"
}

struct NokorikaEntry: TimelineEntry {
  let date: Date
  let remaining: Int?
  let remainingText: String
  let remainingLabel: String
  let monthLabel: String
  let lastBusinessDayText: String
  let totalBusinessDays: Int

  var progress: Double {
    guard let remaining, totalBusinessDays > 0 else { return 0 }
    let done = max(0, totalBusinessDays - remaining)
    return min(1, Double(done) / Double(totalBusinessDays))
  }

  var remainingFraction: Double {
    guard let remaining, totalBusinessDays > 0 else { return 0 }
    return min(1, Double(remaining) / Double(totalBusinessDays))
  }
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> NokorikaEntry {
    NokorikaEntry(
      date: Date(),
      remaining: 12,
      remainingText: "12",
      remainingLabel: "残り営業日",
      monthLabel: "2026年11月",
      lastBusinessDayText: "最終 11/28",
      totalBusinessDays: 20
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (NokorikaEntry) -> Void) {
    completion(buildEntry(for: Date(), isPreview: context.isPreview))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<NokorikaEntry>) -> Void) {
    let defaults = UserDefaults(suiteName: widgetGroupId)
    let remainingJson = defaults?.string(forKey: WidgetKeys.remainingByDate) ?? ""
    let calendar = Calendar.current
    let now = Date()

    var entries: [NokorikaEntry] = []
    for dayOffset in 0..<40 {
      guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { break }
      let startOfDay = calendar.startOfDay(for: day)
      if dayOffset > 0 && startOfDay <= now { continue }
      let entryDate = dayOffset == 0 ? now : startOfDay
      entries.append(buildEntry(for: entryDate, isPreview: false))

      if dayOffset > 0,
         let monthKey = defaults?.string(forKey: WidgetKeys.monthKey),
         monthKeyOf(date: entryDate) != monthKey
      {
        break
      }

      if remainingJson.isEmpty { break }
    }

    if entries.isEmpty {
      entries = [buildEntry(for: now, isPreview: false)]
    }

    let nextMidnight =
      calendar.nextDate(
        after: now,
        matching: DateComponents(hour: 0, minute: 0, second: 0),
        matchingPolicy: .nextTime
      ) ?? now.addingTimeInterval(60 * 60 * 6)

    completion(Timeline(entries: entries, policy: .after(nextMidnight)))
  }

  private func buildEntry(for date: Date, isPreview: Bool) -> NokorikaEntry {
    let defaults = UserDefaults(suiteName: widgetGroupId)
    let remainingJson = defaults?.string(forKey: WidgetKeys.remainingByDate)
    let lastBusinessDay = defaults?.string(forKey: WidgetKeys.lastBusinessDay)
    let monthLabel = defaults?.string(forKey: WidgetKeys.monthLabel)
    let monthKey = defaults?.string(forKey: WidgetKeys.monthKey)
    let total = defaults?.integer(forKey: WidgetKeys.totalBusinessDays) ?? 0
    let currentMonthKey = monthKeyOf(date: date)
    let todayKey = dateKey(of: date)

    let lastText: String
    if let lastBusinessDay, !lastBusinessDay.isEmpty {
      lastText = "最終 \(lastBusinessDay)"
    } else {
      lastText = ""
    }

    if remainingJson == nil || remainingJson?.isEmpty == true || monthKey != currentMonthKey {
      return NokorikaEntry(
        date: date,
        remaining: isPreview ? 12 : nil,
        remainingText: isPreview ? "12" : "—",
        remainingLabel: isPreview ? "残り営業日" : "アプリを開いて同期",
        monthLabel: monthLabel ?? "ノコリカ",
        lastBusinessDayText: lastText,
        totalBusinessDays: isPreview ? 20 : max(total, 0)
      )
    }

    var remaining: Int?
    if let data = remainingJson?.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      if let number = json[todayKey] as? Int {
        remaining = number
      } else if let number = json[todayKey] as? NSNumber {
        remaining = number.intValue
      }
    }

    if let remaining {
      return NokorikaEntry(
        date: date,
        remaining: remaining,
        remainingText: "\(remaining)",
        remainingLabel: "残り営業日",
        monthLabel: monthLabel ?? "ノコリカ",
        lastBusinessDayText: lastText,
        totalBusinessDays: max(total, remaining)
      )
    }

    return NokorikaEntry(
      date: date,
      remaining: nil,
      remainingText: "—",
      remainingLabel: "アプリを開いて同期",
      monthLabel: monthLabel ?? "ノコリカ",
      lastBusinessDayText: lastText,
      totalBusinessDays: max(total, 0)
    )
  }

  private func dateKey(of date: Date) -> String {
    let calendar = Calendar.current
    let y = calendar.component(.year, from: date)
    let m = calendar.component(.month, from: date)
    let d = calendar.component(.day, from: date)
    return String(format: "%04d-%02d-%02d", y, m, d)
  }

  private func monthKeyOf(date: Date) -> String {
    let calendar = Calendar.current
    let y = calendar.component(.year, from: date)
    let m = calendar.component(.month, from: date)
    return String(format: "%04d-%02d", y, m)
  }
}

struct NokorikaWidgetEntryView: View {
  @Environment(\.widgetFamily) private var family
  var entry: NokorikaEntry

  private let ink = Color.white
  private let mist = Color.white.opacity(0.82)
  private let hush = Color.white.opacity(0.58)

  var body: some View {
    Group {
      switch family {
      case .systemMedium:
        mediumLayout
      default:
        smallLayout
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .widgetBackground { widgetChrome }
    .widgetURL(URL(string: "nokorika://"))
  }

  private var smallLayout: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 8) {
        Text(entry.remainingLabel)
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundColor(mist)
          .lineLimit(1)
        Spacer(minLength: 4)
        appIcon(size: 22)
      }

      Spacer(minLength: 4)

      HStack(alignment: .center, spacing: 10) {
        Text(entry.remainingText)
          .font(.system(size: 42, weight: .bold, design: .rounded))
          .foregroundColor(ink)
          .minimumScaleFactor(0.5)
          .lineLimit(1)
          .tracking(-1)

        Spacer(minLength: 0)

        progressRing(lineWidth: 5)
          .frame(width: 46, height: 46)
      }

      Spacer(minLength: 6)

      progressBar
        .padding(.bottom, 6)

      HStack(spacing: 6) {
        Text(entry.monthLabel)
          .font(.system(size: 10, weight: .medium, design: .rounded))
          .foregroundColor(hush)
          .lineLimit(1)
        Spacer(minLength: 0)
        if !entry.lastBusinessDayText.isEmpty {
          Text(entry.lastBusinessDayText)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundColor(hush)
            .lineLimit(1)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }

  private var mediumLayout: some View {
    HStack(alignment: .center, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .center, spacing: 8) {
          Text(entry.remainingLabel)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(mist)
            .lineLimit(1)
          Spacer(minLength: 0)
          appIcon(size: 24)
        }

        Text(entry.remainingText)
          .font(.system(size: 48, weight: .bold, design: .rounded))
          .foregroundColor(ink)
          .minimumScaleFactor(0.5)
          .lineLimit(1)
          .tracking(-1)

        progressBar
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      VStack(spacing: 8) {
        progressRing(lineWidth: 6)
          .frame(width: 64, height: 64)

        VStack(alignment: .leading, spacing: 3) {
          Text(entry.monthLabel)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(ink)
            .lineLimit(1)
          if !entry.lastBusinessDayText.isEmpty {
            Text(entry.lastBusinessDayText)
              .font(.system(size: 11, weight: .medium, design: .rounded))
              .foregroundColor(hush)
              .lineLimit(1)
          }
          if entry.totalBusinessDays > 0, let remaining = entry.remaining {
            Text("全\(entry.totalBusinessDays)日中 \(max(0, entry.totalBusinessDays - remaining))日経過")
              .font(.system(size: 10, weight: .medium, design: .rounded))
              .foregroundColor(hush)
              .lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(width: 120, alignment: .center)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
  }

  private func appIcon(size: CGFloat) -> some View {
    Image("AppLogo")
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
          .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
      )
      .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
      .accessibilityHidden(true)
  }

  private func progressRing(lineWidth: CGFloat) -> some View {
    ZStack {
      Circle()
        .stroke(Color.white.opacity(0.18), lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: entry.remainingFraction)
        .stroke(
          AngularGradient(
            colors: [
              Color.white.opacity(0.95),
              Color(red: 0.70, green: 0.90, blue: 1.0),
              Color.white.opacity(0.75),
            ],
            center: .center
          ),
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
      VStack(spacing: 0) {
        Text(percentText)
          .font(.system(size: lineWidth > 5 ? 12 : 10, weight: .bold, design: .rounded))
          .foregroundColor(ink)
          .minimumScaleFactor(0.7)
          .lineLimit(1)
      }
    }
    .accessibilityLabel("残り割合 \(percentText)")
  }

  private var progressBar: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.white.opacity(0.16))
        Capsule()
          .fill(
            LinearGradient(
              colors: [
                Color.white.opacity(0.95),
                Color(red: 0.72, green: 0.90, blue: 1.0),
              ],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .frame(width: max(6, geo.size.width * entry.remainingFraction))
      }
    }
    .frame(height: 5)
  }

  private var percentText: String {
    guard entry.totalBusinessDays > 0, entry.remaining != nil else { return "—" }
    return "\(Int((entry.remainingFraction * 100).rounded()))%"
  }

  private var widgetChrome: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.10, green: 0.45, blue: 0.86),
          Color(red: 0.05, green: 0.28, blue: 0.62),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      Circle()
        .fill(Color.white.opacity(0.12))
        .frame(width: 120, height: 120)
        .blur(radius: 8)
        .offset(x: 48, y: -42)
    }
  }
}

private extension View {
  @ViewBuilder
  func widgetBackground<Background: View>(
    @ViewBuilder _ background: () -> Background
  ) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      self.containerBackground(for: .widget, content: background)
    } else {
      self.background(background())
    }
  }
}

@main
struct NokorikaWidget: Widget {
  let kind: String = "NokorikaWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      NokorikaWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("残り営業日")
    .description("今月の残り営業日と最終営業日を表示します")
    .supportedFamilies([.systemSmall, .systemMedium])
    .contentMarginsDisabled()
  }
}
