import SwiftUI
import PhotosUI
import WidgetKit
import ImageIO

// MARK: - Цветовая схема (OLED Black, Grey, White, Crimson Red)
enum CreepTheme {
    static let bg = Color.black
    static let card = Color(red: 0.09, green: 0.09, blue: 0.10)
    static let border = Color(red: 0.20, green: 0.20, blue: 0.22)
    static let textGrey = Color(red: 0.58, green: 0.58, blue: 0.62)
    static let red = Color(red: 1.0, green: 0.12, blue: 0.12)
}

// MARK: - Тактильный отклик iPhone 14 Pro (Taptic Engine)
enum Haptics {
    private static let impact = UIImpactFeedbackGenerator(style: .rigid)
    private static let notify = UINotificationFeedbackGenerator()
    
    static func tap() {
        impact.prepare()
        impact.impactOccurred()
    }
    static func success() {
        notify.prepare()
        notify.notificationOccurred(.success)
    }
}

// MARK: - Оптимизатор изображений (Downsampling без нагрузки на RAM)
enum ImageOptimizer {
    static func downsampleAndSave(data: Data, id: UUID) -> String? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1080
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.82) else { return nil }
        
        let filename = "\(id.uuidString).jpg"
        let url = getDocumentsDirectory().appendingPathComponent(filename)
        try? jpegData.write(to: url, options: .atomic)
        return filename
    }
    
    static func loadImage(filename: String) -> UIImage? {
        let url = getDocumentsDirectory().appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    
    static func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

// MARK: - Модели данных
struct ExerciseItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var sets: Int
    var reps: String
    var weightKg: Double
    var completedSets: Int = 0
}

struct FoodEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var calories: Int
    var protein: Int
    var fats: Int
    var carbs: Int
}

struct ProgressPhotoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var monthLabel: String
    var bodyWeight: Double
    var filename: String
    var date: Date = Date()
}

// MARK: - Единое хранилище состояния (Оптимизировано)
final class AppStorageManager: ObservableObject {
    static let sharedSuite = UserDefaults(suiteName: "group.bycreep.app") ?? .standard
    
    @Published var workoutDays: Set<Int> = [0, 2, 4] { // 0 = пн, 1 = вт ... 6 = вс
        didSet { saveWorkoutDays() }
    }
    @Published var exercises: [ExerciseItem] = [] {
        didSet { saveCodable(exercises, key: "exercises") }
    }
    @Published var foods: [FoodEntry] = [] {
        didSet { saveCodable(foods, key: "foods") }
    }
    @Published var photos: [ProgressPhotoItem] = [] {
        didSet { saveCodable(photos, key: "photos") }
    }
    
    @AppStorage("user_weight") var userWeight: Double = 85.0
    @AppStorage("user_height") var userHeight: Double = 182.0
    @AppStorage("user_focus") var userFocus: Int = 0 // 0: Верх (Грудь/Спина), 1: Тяжелый Сплит, 2: Фуллбади
    
    init() {
        if let savedDays = Self.sharedSuite.array(forKey: "workoutDays") as? [Int] {
            workoutDays = Set(savedDays)
        } else {
            saveWorkoutDays()
        }
        exercises = loadCodable(key: "exercises") ?? [
            ExerciseItem(name: "Жим штанги лежа (Тяжелый)", sets: 4, reps: "6-8", weightKg: 90),
            ExerciseItem(name: "Подтягивания с доп. весом", sets: 4, reps: "8", weightKg: 15),
            ExerciseItem(name: "Тяга штанги в наклоне", sets: 4, reps: "8-10", weightKg: 80),
            ExerciseItem(name: "Жим гантелей на наклонной", sets: 3, reps: "8-10", weightKg: 34)
        ]
        foods = loadCodable(key: "foods") ?? []
        photos = loadCodable(key: "photos") ?? []
    }
    
    private func saveWorkoutDays() {
        let array = Array(workoutDays)
        Self.sharedSuite.set(array, forKey: "workoutDays")
        UserDefaults.standard.set(array, forKey: "workoutDays")
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func saveCodable<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    private func loadCodable<T: Decodable>(key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    
    // Расчет дневной нормы КБЖУ для тяжелого силового тренинга
    var targetCalories: Int {
        Int((10 * userWeight + 6.25 * userHeight - 120) * 1.65)
    }
    var targetProtein: Int { Int(userWeight * 2.1) }
    var targetFats: Int { Int(userWeight * 1.0) }
    var targetCarbs: Int {
        max(100, (targetCalories - (targetProtein * 4 + targetFats * 9)) / 4)
    }
    
    // Генератор тяжелой тренировки от параметров тела
    func generateHeavyWorkout() {
        Haptics.success()
        let w = userWeight
        var generated: [ExerciseItem] = []
        
        switch userFocus {
        case 0: // Мощный Верх (Грудь + Спина + Плечи)
            generated = [
                ExerciseItem(name: "Жим штанги лежа", sets: 5, reps: "5", weightKg: roundTo2_5(w * 1.1)),
                ExerciseItem(name: "Подтягивания широким хватом с весом", sets: 4, reps: "6-8", weightKg: roundTo2_5(w * 0.2)),
                ExerciseItem(name: "Тяга штанги в наклоне к поясу", sets: 4, reps: "8", weightKg: roundTo2_5(w * 0.95)),
                ExerciseItem(name: "Жим гантелей на наклонной (по 1 гантели)", sets: 4, reps: "8-10", weightKg: roundTo2_5(w * 0.42)),
                ExerciseItem(name: "Армейский жим стоя", sets: 4, reps: "6-8", weightKg: roundTo2_5(w * 0.65)),
                ExerciseItem(name: "Отжимания на брусьях с весом", sets: 3, reps: "8-10", weightKg: roundTo2_5(w * 0.25))
            ]
            workoutDays = [0, 2, 4, 5] // пн, ср, пт, сб
        case 1: // Тяжелая База (Пауэр-билдинг)
            generated = [
                ExerciseItem(name: "Приседания со штангой", sets: 5, reps: "5", weightKg: roundTo2_5(w * 1.35)),
                ExerciseItem(name: "Жим штанги лежа", sets: 5, reps: "5", weightKg: roundTo2_5(w * 1.1)),
                ExerciseItem(name: "Становая тяга", sets: 4, reps: "5", weightKg: roundTo2_5(w * 1.55)),
                ExerciseItem(name: "Тяга Т-грифа", sets: 4, reps: "8", weightKg: roundTo2_5(w * 0.85)),
                ExerciseItem(name: "Подъем штанги на бицепс стоя", sets: 4, reps: "8", weightKg: roundTo2_5(w * 0.5))
            ]
            workoutDays = [0, 2, 4] // пн, ср, пт
        default: // Интенсивный Сплит (Гипертрофия)
            generated = [
                ExerciseItem(name: "Жим штанги на наклонной скамье", sets: 4, reps: "6-8", weightKg: roundTo2_5(w * 0.95)),
                ExerciseItem(name: "Тяга верхнего блока к груди", sets: 4, reps: "8-10", weightKg: roundTo2_5(w * 0.9)),
                ExerciseItem(name: "Жим ногами в тренажере", sets: 4, reps: "10", weightKg: roundTo2_5(w * 2.4)),
                ExerciseItem(name: "Махи гантелями в стороны", sets: 4, reps: "12-15", weightKg: 14),
                ExerciseItem(name: "Французский жим с EZ-грифом", sets: 4, reps: "8-10", weightKg: roundTo2_5(w * 0.45))
            ]
            workoutDays = [1, 3, 5] // вт, чт, сб
        }
        exercises = generated
    }
    
    private func roundTo2_5(_ val: Double) -> Double {
        (val / 2.5).rounded() * 2.5
    }
}

// MARK: - Точка входа
@main
struct bycreepApp: App {
    @StateObject private var store = AppStorageManager()
    
    init() {
        UITabBar.appearance().backgroundColor = UIColor.black
        UITabBar.appearance().unselectedItemTintColor = UIColor.darkGray
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Главный экран с вкладками
struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            WorkoutProgramView()
                .tabItem {
                    Label("Тренировка", systemImage: "dumbbell.fill")
                }
                .tag(0)
            
            HeavyGeneratorView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Идеал База", systemImage: "bolt.heart.fill")
                }
                .tag(1)
            
            ProgressPhotosView()
                .tabItem {
                    Label("Форма", systemImage: "camera.viewfinder")
                }
                .tag(2)
            
            NutritionTrackerView()
                .tabItem {
                    Label("Питание", systemImage: "flame.fill")
                }
                .tag(3)
        }
        .tint(CreepTheme.red)
    }
}

// MARK: - ВКЛАДКА 1: Программа тренировок + Превью Виджета
struct WorkoutProgramView: View {
    @EnvironmentObject var store: AppStorageManager
    @State private var showAddSheet = false
    @State private var newName = ""
    @State private var newSets = "4"
    @State private var newReps = "8-10"
    @State private var newWeight = "80"
    
    private let dayLabels = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]
    
    var body: some View {
        NavigationStack {
            ZStack {
                CreepTheme.bg.ignoresSafeArea()
                
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 18) {
                        // Блок синхронизации с виджетом (1-в-1 как на главном экране)
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("BYCREEP // ДНИ ТРЕНИРОВОК")
                                    .font(.system(size: 13, weight: .black, design: .monospaced))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("НАЖМИ НА ДЕНЬ")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(CreepTheme.textGrey)
                            }
                            
                            HStack(spacing: 0) {
                                ForEach(0..<7, id: \.self) { index in
                                    let isWorkout = store.workoutDays.contains(index)
                                    Button {
                                        Haptics.tap()
                                        if isWorkout {
                                            store.workoutDays.remove(index)
                                        } else {
                                            store.workoutDays.insert(index)
                                        }
                                    } label: {
                                        VStack(spacing: 8) {
                                            Circle()
                                                .fill(isWorkout ? CreepTheme.red : Color.clear)
                                                .frame(width: 28, height: 28)
                                                .overlay(
                                                    Circle()
                                                        .stroke(isWorkout ? CreepTheme.red : Color.white, lineWidth: 2)
                                                )
                                                .shadow(color: isWorkout ? CreepTheme.red : .clear, radius: 8)
                                                .shadow(color: isWorkout ? CreepTheme.red.opacity(0.7) : .clear, radius: 14)
                                            
                                            Text(dayLabels[index])
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .padding(16)
                        .background(CreepTheme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(CreepTheme.border, lineWidth: 1)
                        )
                        .cornerRadius(16)
                        
                        // Заголовок упражнений
                        HStack {
                            Text("МОЯ ПРОГРАММА")
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundColor(CreepTheme.textGrey)
                            Spacer()
                            Button {
                                Haptics.tap()
                                for i in store.exercises.indices {
                                    store.exercises[i].completedSets = 0
                                }
                            } label: {
                                Text("Сбросить подходы")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(CreepTheme.red)
                            }
                        }
                        
                        // Список упражнений
                        ForEach($store.exercises) { $item in
                            ExerciseCardView(exercise: $item) {
                                Haptics.tap()
                                store.exercises.removeAll { $0.id == item.id }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("bycreep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Haptics.tap()
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(CreepTheme.red)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddExerciseSheet(
                    name: $newName,
                    sets: $newSets,
                    reps: $newReps,
                    weight: $newWeight
                ) {
                    let s = Int(newSets) ?? 4
                    let w = Double(newWeight.replacingOccurrences(of: ",", with: ".")) ?? 60
                    let ex = ExerciseItem(
                        name: newName.isEmpty ? "Базовое упражнение" : newName,
                        sets: max(1, s),
                        reps: newReps.isEmpty ? "8-10" : newReps,
                        weightKg: w
                    )
                    store.exercises.append(ex)
                    newName = ""
                    showAddSheet = false
                    Haptics.success()
                }
                .presentationDetents([.medium])
            }
        }
    }
}

struct ExerciseCardView: View {
    @Binding var exercise: ExerciseItem
    var onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("\(exercise.sets) подх. × \(exercise.reps) повт. • \(String(format: "%.1f", exercise.weightKg)) кг")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(CreepTheme.textGrey)
                }
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(CreepTheme.textGrey)
                }
            }
            
            // Интерактивные кружки подходов
            HStack(spacing: 10) {
                ForEach(1...max(1, exercise.sets), id: \.self) { setNumber in
                    let isDone = setNumber <= exercise.completedSets
                    Button {
                        Haptics.tap()
                        if exercise.completedSets == setNumber {
                            exercise.completedSets -= 1
                        } else {
                            exercise.completedSets = setNumber
                        }
                    } label: {
                        Text("\(setNumber)")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(isDone ? CreepTheme.red : Color.clear)
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(isDone ? CreepTheme.red : Color.white.opacity(0.6), lineWidth: 1.5)
                            )
                            .shadow(color: isDone ? CreepTheme.red.opacity(0.8) : .clear, radius: 6)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if exercise.completedSets == exercise.sets {
                    Text("ВЫПОЛНЕНО")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(CreepTheme.red)
                }
            }
        }
        .padding(16)
        .background(CreepTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(exercise.completedSets == exercise.sets ? CreepTheme.red.opacity(0.7) : CreepTheme.border, lineWidth: 1)
        )
        .cornerRadius(14)
    }
}

struct AddExerciseSheet: View {
    @Binding var name: String
    @Binding var sets: String
    @Binding var reps: String
    @Binding var weight: String
    var onSave: () -> Void
    
    var body: some View {
        ZStack {
            CreepTheme.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("НОВОЕ УПРАЖНЕНИЕ")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.white)
                    .padding(.top, 10)
                
                TextField("Название (напр. Жим лежа)", text: $name)
                    .padding(12)
                    .background(CreepTheme.card)
                    .cornerRadius(10)
                    .foregroundColor(.white)
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        Text("Подходы").font(.caption).foregroundColor(CreepTheme.textGrey)
                        TextField("4", text: $sets)
                            .keyboardType(.numberPad)
                            .padding(12)
                            .background(CreepTheme.card)
                            .cornerRadius(10)
                    }
                    VStack(alignment: .leading) {
                        Text("Повторения").font(.caption).foregroundColor(CreepTheme.textGrey)
                        TextField("6-8", text: $reps)
                            .padding(12)
                            .background(CreepTheme.card)
                            .cornerRadius(10)
                    }
                    VStack(alignment: .leading) {
                        Text("Вес (кг)").font(.caption).foregroundColor(CreepTheme.textGrey)
                        TextField("85", text: $weight)
                            .keyboardType(.decimalPad)
                            .padding(12)
                            .background(CreepTheme.card)
                            .cornerRadius(10)
                    }
                }
                
                Button(action: onSave) {
                    Text("ДОБАВИТЬ В ПРОГРАММУ")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(CreepTheme.red)
                        .cornerRadius(12)
                        .shadow(color: CreepTheme.red.opacity(0.6), radius: 10)
                }
                .padding(.top, 8)
                Spacer()
            }
            .padding(20)
        }
    }
}

// MARK: - ВКЛАДКА 2: Умный Генератор Тяжелой Тренировки
struct HeavyGeneratorView: View {
    @EnvironmentObject var store: AppStorageManager
    @Binding var selectedTab: Int
    
    private let focuses = [
        "Мощный Верх (Грудь + Спина + Плечи)",
        "Тяжелая Силовая База (3 дня)",
        "Интенсивный Сплит на Массу"
    ]
    
    var bmi: Double {
        let hMeters = max(1.0, store.userHeight / 100.0)
        return store.userWeight / (hMeters * hMeters)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                CreepTheme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Карточка антропометрии
                        VStack(alignment: .leading, spacing: 16) {
                            Text("ТВОИ ПАРАМЕТРЫ")
                                .font(.system(size: 13, weight: .black))
                                .foregroundColor(CreepTheme.red)
                            
                            HStack {
                                Text("Рост: \(Int(store.userHeight)) см")
                                    .font(.system(size: 16, weight: .bold))
                                Spacer()
                                Stepper("", value: $store.userHeight, in: 140...220, step: 1)
                                    .labelsHidden()
                            }
                            
                            HStack {
                                Text("Вес: \(String(format: "%.1f", store.userWeight)) кг")
                                    .font(.system(size: 16, weight: .bold))
                                Spacer()
                                Stepper("", value: $store.userWeight, in: 45...160, step: 0.5)
                                    .labelsHidden()
                            }
                            
                            Divider().background(CreepTheme.border)
                            
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Индекс массы (ИМТ)")
                                        .font(.caption)
                                        .foregroundColor(CreepTheme.textGrey)
                                    Text(String(format: "%.1f", bmi))
                                        .font(.system(size: 20, weight: .black))
                                        .foregroundColor(.white)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("Расчетный жим (5x5)")
                                        .font(.caption)
                                        .foregroundColor(CreepTheme.textGrey)
                                    Text("\(Int((store.userWeight * 1.1 / 2.5).rounded() * 2.5)) кг")
                                        .font(.system(size: 20, weight: .black))
                                        .foregroundColor(CreepTheme.red)
                                }
                            }
                        }
                        .padding(16)
                        .background(CreepTheme.card)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CreepTheme.border, lineWidth: 1))
                        
                        // Выбор специализации
                        VStack(alignment: .leading, spacing: 12) {
                            Text("СПЕЦИАЛИЗАЦИЯ ТЯЖЕЛОГО ЦИКЛА")
                                .font(.system(size: 13, weight: .black))
                                .foregroundColor(CreepTheme.textGrey)
                            
                            ForEach(0..<focuses.count, id: \.self) { idx in
                                let isSelected = store.userFocus == idx
                                Button {
                                    Haptics.tap()
                                    store.userFocus = idx
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(isSelected ? CreepTheme.red : Color.clear)
                                            .frame(width: 18, height: 18)
                                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                            .shadow(color: isSelected ? CreepTheme.red : .clear, radius: 6)
                                        
                                        Text(focuses[idx])
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(.white)
                                        Spacer()
                                    }
                                    .padding(14)
                                    .background(CreepTheme.card)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(isSelected ? CreepTheme.red : CreepTheme.border, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        Button {
                            store.generateHeavyWorkout()
                            selectedTab = 0
                        } label: {
                            HStack {
                                Image(systemName: "flame.fill")
                                Text("СОСТАВИТЬ ТЯЖЕЛУЮ ПРОГРАММУ")
                            }
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(CreepTheme.red)
                            .cornerRadius(14)
                            .shadow(color: CreepTheme.red.opacity(0.7), radius: 12)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Идеальная Тренировка")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - ВКЛАДКА 3: Фото Прогресса (Ежемесячное сравнение До / После)
struct ProgressPhotosView: View {
    @EnvironmentObject var store: AppStorageManager
    @State private var selectedItem: PhotosPickerItem?
    @State private var monthInput: String = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: Date()).capitalized
    }()
    
    @State private var leftPhotoIndex: Int = 0
    @State private var rightPhotoIndex: Int = 0
    @State private var sliderRatio: CGFloat = 0.5
    
    var body: some View {
        NavigationStack {
            ZStack {
                CreepTheme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Панель добавления нового фото за месяц
                        VStack(spacing: 12) {
                            HStack {
                                TextField("Месяц (напр. Октябрь 2026)", text: $monthInput)
                                    .padding(12)
                                    .background(Color.black)
                                    .cornerRadius(10)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(CreepTheme.border, lineWidth: 1))
                                
                                PhotosPicker(selection: $selectedItem, matching: .images) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "camera.fill")
                                        Text("+ ФОТО")
                                    }
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(CreepTheme.red)
                                    .cornerRadius(10)
                                    .shadow(color: CreepTheme.red.opacity(0.6), radius: 8)
                                }
                            }
                        }
                        .padding(14)
                        .background(CreepTheme.card)
                        .cornerRadius(14)
                        .onChange(of: selectedItem) { newItem in
                            guard let newItem else { return }
                            Task {
                                if let data = try? await newItem.loadTransferable(type: Data.self) {
                                    let id = UUID()
                                    if let filename = ImageOptimizer.downsampleAndSave(data: data, id: id) {
                                        await MainActor.run {
                                            let entry = ProgressPhotoItem(
                                                id: id,
                                                monthLabel: monthInput,
                                                bodyWeight: store.userWeight,
                                                filename: filename
                                            )
                                            store.photos.insert(entry, at: 0)
                                            if store.photos.count >= 2 {
                                                leftPhotoIndex = min(1, store.photos.count - 1)
                                                rightPhotoIndex = 0
                                            }
                                            Haptics.success()
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Блок интерактивного сравнения 2 фотографий (Шторка До / После)
                        if store.photos.count >= 2 {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("СРАВНЕНИЕ ФОРМЫ (ДВИГАЙ ПОЛЗУНОК)")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundColor(CreepTheme.red)
                                
                                HStack {
                                    Picker("До", selection: $leftPhotoIndex) {
                                        ForEach(store.photos.indices, id: \.self) { i in
                                            Text(store.photos[i].monthLabel).tag(i)
                                        }
                                    }
                                    .tint(.white)
                                    Spacer()
                                    Image(systemName: "arrow.left.and.right")
                                        .foregroundColor(CreepTheme.red)
                                    Spacer()
                                    Picker("После", selection: $rightPhotoIndex) {
                                        ForEach(store.photos.indices, id: \.self) { i in
                                            Text(store.photos[i].monthLabel).tag(i)
                                        }
                                    }
                                    .tint(.white)
                                }
                                
                                PhotoCompareSlider(
                                    leftPhoto: store.photos[min(leftPhotoIndex, store.photos.count - 1)],
                                    rightPhoto: store.photos[min(rightPhotoIndex, store.photos.count - 1)],
                                    ratio: $sliderRatio
                                )
                                .frame(height: 360)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(CreepTheme.border, lineWidth: 1))
                            }
                            .padding(14)
                            .background(CreepTheme.card)
                            .cornerRadius(16)
                        }
                        
                        // Архив по месяцам
                        LazyVStack(spacing: 14) {
                            ForEach(store.photos) { item in
                                HStack(spacing: 14) {
                                    if let uiImg = ImageOptimizer.loadImage(filename: item.filename) {
                                        Image(uiImage: uiImg)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.monthLabel)
                                            .font(.system(size: 17, weight: .bold))
                                            .foregroundColor(.white)
                                        Text("Вес формы: \(String(format: "%.1f", item.bodyWeight)) кг")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(CreepTheme.red)
                                    }
                                    Spacer()
                                    Button {
                                        Haptics.tap()
                                        store.photos.removeAll { $0.id == item.id }
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(CreepTheme.textGrey)
                                    }
                                }
                                .padding(12)
                                .background(CreepTheme.card)
                                .cornerRadius(14)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Фото Прогресса")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct PhotoCompareSlider: View {
    let leftPhoto: ProgressPhotoItem
    let rightPhoto: ProgressPhotoItem
    @Binding var ratio: CGFloat
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if let rightImg = ImageOptimizer.loadImage(filename: rightPhoto.filename) {
                    Image(uiImage: rightImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                
                if let leftImg = ImageOptimizer.loadImage(filename: leftPhoto.filename) {
                    Image(uiImage: leftImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .mask(
                            HStack(spacing: 0) {
                                Rectangle().frame(width: geo.size.width * ratio)
                                Spacer(minLength: 0)
                            }
                        )
                }
                
                // Красная неоновая линия разделителя
                Rectangle()
                    .fill(CreepTheme.red)
                    .frame(width: 3, height: geo.size.height)
                    .shadow(color: CreepTheme.red, radius: 8)
                    .offset(x: geo.size.width * ratio - 1.5)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newRatio = value.location.x / max(1, geo.size.width)
                        ratio = min(max(newRatio, 0.05), 0.95)
                    }
            )
        }
    }
}

// MARK: - ВКЛАДКА 4: Питание и КБЖУ
struct NutritionTrackerView: View {
    @EnvironmentObject var store: AppStorageManager
    @State private var foodTitle = ""
    @State private var kcalText = ""
    @State private var protText = ""
    
    var totalKcal: Int { store.foods.reduce(0) { $0 + $1.calories } }
    var totalProt: Int { store.foods.reduce(0) { $0 + $1.protein } }
    var totalFats: Int { store.foods.reduce(0) { $0 + $1.fats } }
    var totalCarbs: Int { store.foods.reduce(0) { $0 + $1.carbs } }
    
    var body: some View {
        NavigationStack {
            ZStack {
                CreepTheme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        // Сводка КБЖУ
                        VStack(spacing: 14) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("КАЛОРИИ ЗА ДЕНЬ")
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundColor(CreepTheme.textGrey)
                                    Text("\(totalKcal) / \(store.targetCalories) ккал")
                                        .font(.system(size: 24, weight: .black))
                                        .foregroundColor(.white)
                                }
                                Spacer()
                                Button("Новый день") {
                                    Haptics.tap()
                                    store.foods.removeAll()
                                }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(CreepTheme.red)
                            }
                            
                            HStack(spacing: 12) {
                                MacroPill(label: "БЕЛКИ", current: totalProt, target: store.targetProtein)
                                MacroPill(label: "ЖИРЫ", current: totalFats, target: store.targetFats)
                                MacroPill(label: "УГЛЕВОДЫ", current: totalCarbs, target: store.targetCarbs)
                            }
                        }
                        .padding(16)
                        .background(CreepTheme.card)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CreepTheme.border, lineWidth: 1))
                        
                        // Быстрые пресеты спорт-питания
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                QuickFoodButton(title: "+ Сывороточный Протеин", kcal: 130, p: 26, f: 2, c: 3)
                                QuickFoodButton(title: "+ Куриная грудка и рис", kcal: 520, p: 48, f: 7, c: 65)
                                QuickFoodButton(title: "+ 4 Яйца и тост", kcal: 410, p: 28, f: 22, c: 24)
                                QuickFoodButton(title: "+ Пачка творога 5%", kcal: 240, p: 36, f: 10, c: 4)
                            }
                        }
                        
                        // Ручное добавление
                        HStack(spacing: 8) {
                            TextField("Прием пищи", text: $foodTitle)
                                .padding(10)
                                .background(CreepTheme.card)
                                .cornerRadius(10)
                            TextField("Ккал", text: $kcalText)
                                .keyboardType(.numberPad)
                                .frame(width: 65)
                                .padding(10)
                                .background(CreepTheme.card)
                                .cornerRadius(10)
                            TextField("Белок", text: $protText)
                                .keyboardType(.numberPad)
                                .frame(width: 65)
                                .padding(10)
                                .background(CreepTheme.card)
                                .cornerRadius(10)
                            Button {
                                guard let k = Int(kcalText) else { return }
                                let p = Int(protText) ?? 0
                                store.foods.insert(
                                    FoodEntry(title: foodTitle.isEmpty ? "Прием пищи" : foodTitle, calories: k, protein: p, fats: 10, carbs: 25),
                                    at: 0
                                )
                                foodTitle = ""
                                kcalText = ""
                                protText = ""
                                Haptics.tap()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .black))
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(CreepTheme.red)
                                    .cornerRadius(10)
                            }
                        }
                        
                        LazyVStack(spacing: 10) {
                            ForEach(store.foods) { f in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(f.title)
                                            .font(.system(size: 15, weight: .bold))
                                        Text("Б: \(f.protein)г • Ж: \(f.fats)г • У: \(f.carbs)г")
                                            .font(.caption)
                                            .foregroundColor(CreepTheme.textGrey)
                                    }
                                    Spacer()
                                    Text("\(f.calories) ккал")
                                        .font(.system(size: 15, weight: .black))
                                        .foregroundColor(CreepTheme.red)
                                }
                                .padding(14)
                                .background(CreepTheme.card)
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Питание")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    @ViewBuilder
    private func QuickFoodButton(title: String, kcal: Int, p: Int, f: Int, c: Int) -> some View {
        Button {
            Haptics.tap()
            store.foods.insert(FoodEntry(title: title.replacingOccurrences(of: "+ ", with: ""), calories: kcal, protein: p, fats: f, carbs: c), at: 0)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(CreepTheme.card)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(CreepTheme.red.opacity(0.6), lineWidth: 1))
                .cornerRadius(10)
        }
    }
}

struct MacroPill: View {
    let label: String
    let current: Int
    let target: Int
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(CreepTheme.textGrey)
            Text("\(current)/\(target)г")
                .font(.system(size: 14, weight: .black))
                .foregroundColor(current >= target ? CreepTheme.red : .white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.black)
        .cornerRadius(10)
    }
}
