import Foundation
public enum DocumentCategory: String, Codable, CaseIterable, Sendable {
    case tickets = "Tickets", hotels = "Hotels", insurance = "Insurance", identity = "Identity", other = "Other"
}
