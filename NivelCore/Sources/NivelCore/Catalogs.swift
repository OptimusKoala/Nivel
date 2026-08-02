import Foundation

public enum Catalogs {
    static func load<T: Decodable>(_ file: String) throws -> T {
        guard let url = Bundle.module.url(forResource: file, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
    public static func quests() throws -> [Quest] { try load("quests") }
    public static func badges() throws -> [Badge] { try load("badges") }
    public static func activities() throws -> [Activity] { try load("activities") }
    public static func sessions() throws -> [ActivitySession] { try load("sessions") }
    public static func foods() throws -> [FoodItem] { try load("foods") }
    public static func compositions() throws -> [String: [MealComponent]] { try load("compositions") }
}
