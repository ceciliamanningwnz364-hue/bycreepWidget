import WidgetKit
import SwiftUI

struct CreepWidgetEntry: TimelineEntry {
    let date: Date
    let workoutDays: Set<Int> // 0 = пн ... 6 = вс
    let todayIndex: Int
}

struct CreepWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CreepWidgetEntry {
        CreepWidgetEntry(date: Date(), workoutDays: [0, 2, 4], todayIndex: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (CreepWidgetEntry) -> Void) {
        completion(loadCurrentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CreepWidgetEntry>) -> Void) {
        let entry = loadCurrentEntry()
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func loadCurrentEntry() -> CreepWidgetEntry {
        let shared = UserDefaults(suiteName: "group.bycreep.app")
        let saved = (shared?.array(forKey: "workoutDays") as? [Int])
            ?? (UserDefaults.standard.array(forKey: "workoutDays") as? [Int])
            ?? [0, 2, 4]
        
        // Вычисляем текущий день недели (0 = пн ... 6 = вс)
        let weekday = Calendar.current.component(.weekday, from: Date())
        let mondayBasedIndex = (weekday + 5) % 7
        
        return CreepWidgetEntry(date: Date(), workoutDays: Set(saved), todayIndex: mondayBasedIndex)
    }
}

struct CreepWidgetView: View {
    var entry: CreepWidgetProvider.Entry
    @Environment(\.widgetFamily) var family
    
    private let days = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]
    private let neonRed = Color(red: 1.0, green: 0.12, blue: 0.12)
    
    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 12 : 16) {
            // Верхняя шапка виджета
            HStack {
                Text("bycreep")
                    .font(.system(size: family == .systemSmall ? 14 : 16, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                
                Spacer()
                
                if entry.workoutDays.contains(entry.todayIndex) {
                    Text("ТРЕНИРОВКА")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(neonRed)
                        .shadow(color: neonRed, radius: 4)
                } else {
                    Text("ОТДЫХ")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.gray)
                }
            }
            
            // Ряд из 7 кругов и дней недели под ними
            HStack(spacing: family == .systemSmall ? 4 : 0) {
                ForEach(0..<7, id: \.self) { index in
                    let isWorkoutDay = entry.workoutDays.contains(index)
                    let isToday = (index == entry.todayIndex)
                    let circleSize: CGFloat = family == .systemSmall ? 16 : 28
                    
                    VStack(spacing: family == .systemSmall ? 6 : 8) {
                        ZStack {
                            Circle()
                                .fill(isWorkoutDay ? neonRed : Color.clear)
                                .frame(width: circleSize, height: circleSize)
                                .overlay(
                                    Circle()
                                        .stroke(isWorkoutDay ? neonRed : Color.white, lineWidth: isToday ? 2.2 : 1.6)
                                )
                                .shadow(color: isWorkoutDay ? neonRed : .clear, radius: 6)
                                .shadow(color: isWorkoutDay ? neonRed.opacity(0.85) : .clear, radius: 11)
                            
                            // Если сегодня день тренировки — белая точка-индикатор в центре
                            if isToday && isWorkoutDay {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        
                        Text(days[index])
                            .font(.system(size: family == .systemSmall ? 9 : 12, weight: isToday ? .black : .bold))
                            .foregroundColor(isToday && isWorkoutDay ? neonRed : .white)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(family == .systemSmall ? 12 : 16)
        .widgetBlackBackground()
    }
}

extension View {
    @ViewBuilder
    func widgetBlackBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) {
                Color.black
            }
        } else {
            self.background(Color.black)
        }
    }
}

@main
struct bycreepWidget: Widget {
    let kind: String = "bycreepWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CreepWidgetProvider()) { entry in
            CreepWidgetView(entry: entry)
        }
        .configurationDisplayName("bycreep — Дни Тренировок")
        .description("Чёрно-бело-красный трекер тренировочной недели")
        .supportedFamilies([.systemMedium, .systemSmall])
    }
}
