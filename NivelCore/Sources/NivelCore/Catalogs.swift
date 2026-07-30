import Foundation

public struct Dish: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let emoji: String
    public let kcal: Int
    public let slots: [MealSlot]
    public init(id: String, name: String, emoji: String, kcal: Int, slots: [MealSlot]) {
        self.id = id; self.name = name; self.emoji = emoji; self.kcal = kcal; self.slots = slots
    }
}

public struct Extra: Codable, Identifiable, Hashable, Sendable {
    public enum Category: String, Codable, Sendable { case dessert, drink }
    public let id: String
    public let name: String
    public let emoji: String
    public let kcal: Int
    public let category: Category
    public init(id: String, name: String, emoji: String, kcal: Int, category: Category) {
        self.id = id; self.name = name; self.emoji = emoji; self.kcal = kcal; self.category = category
    }
}

public enum Catalogs {
    static func load<T: Decodable>(_ file: String) throws -> T {
        guard let url = Bundle.module.url(forResource: file, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
    public static func dishes() throws -> [Dish] { try load("dishes") }
    public static func extras() throws -> [Extra] { try load("extras") }
    public static func quests() throws -> [Quest] { try load("quests") }
    public static func badges() throws -> [Badge] { try load("badges") }
    public static func activities() throws -> [Activity] { try load("activities") }
    public static func sessions() throws -> [ActivitySession] { try load("sessions") }
}
