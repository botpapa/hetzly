/// What a `CostItem` represents, for grouping/iconography in the UI.
public enum CostKind: String, Sendable, Codable, CaseIterable {
    case server
    case volume
    case primaryIP
    case floatingIP
    case loadBalancer
    case backup
    case dedicated
    case other
}
