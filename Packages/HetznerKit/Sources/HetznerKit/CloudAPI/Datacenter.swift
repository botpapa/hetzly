import Foundation

public struct Datacenter: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let description: String
    public let location: Location

    enum CodingKeys: String, CodingKey {
        case id, name, description, location
    }

    public init(id: Int, name: String, description: String, location: Location) {
        self.id = id
        self.name = name
        self.description = description
        self.location = location
    }
}

public struct Location: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let description: String
    public let country: String
    public let city: String
    public let latitude: Double
    public let longitude: Double
    public let networkZone: String

    enum CodingKeys: String, CodingKey {
        case id, name, description, country, city, latitude, longitude
        case networkZone = "network_zone"
    }

    public init(
        id: Int,
        name: String,
        description: String,
        country: String,
        city: String,
        latitude: Double,
        longitude: Double,
        networkZone: String
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.country = country
        self.city = city
        self.latitude = latitude
        self.longitude = longitude
        self.networkZone = networkZone
    }
}
