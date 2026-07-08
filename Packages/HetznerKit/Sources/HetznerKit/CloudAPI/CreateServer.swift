import Foundation

/// Request body for `POST /servers`. Optional fields are omitted from the
/// wire payload when `nil` (Swift's synthesized `Encodable` conformance uses
/// `encodeIfPresent` for `Optional` stored properties).
public struct CreateServerRequest: Encodable, Sendable, Equatable {
    public var name: String
    /// Server type ID or name, e.g. `"cx22"`.
    public var serverType: String
    /// Image ID or name, e.g. `"ubuntu-24.04"`.
    public var image: String
    public var location: String?
    public var datacenter: String?
    public var sshKeys: [String]
    public var volumes: [Int]
    public var networks: [Int]
    public var firewalls: [FirewallReference]
    public var userData: String?
    public var labels: [String: String]
    public var automount: Bool?
    public var backups: Bool?
    public var publicNet: PublicNetSelection?
    public var placementGroup: Int?
    public var startAfterCreate: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case serverType = "server_type"
        case image
        case location
        case datacenter
        case sshKeys = "ssh_keys"
        case volumes
        case networks
        case firewalls
        case userData = "user_data"
        case labels
        case automount
        case backups
        case publicNet = "public_net"
        case placementGroup = "placement_group"
        case startAfterCreate = "start_after_create"
    }

    public init(
        name: String,
        serverType: String,
        image: String,
        location: String? = nil,
        datacenter: String? = nil,
        sshKeys: [String] = [],
        volumes: [Int] = [],
        networks: [Int] = [],
        firewalls: [FirewallReference] = [],
        userData: String? = nil,
        labels: [String: String] = [:],
        automount: Bool? = nil,
        backups: Bool? = nil,
        publicNet: PublicNetSelection? = nil,
        placementGroup: Int? = nil,
        startAfterCreate: Bool? = nil
    ) {
        self.name = name
        self.serverType = serverType
        self.image = image
        self.location = location
        self.datacenter = datacenter
        self.sshKeys = sshKeys
        self.volumes = volumes
        self.networks = networks
        self.firewalls = firewalls
        self.userData = userData
        self.labels = labels
        self.automount = automount
        self.backups = backups
        self.publicNet = publicNet
        self.placementGroup = placementGroup
        self.startAfterCreate = startAfterCreate
    }

    public struct FirewallReference: Encodable, Sendable, Equatable {
        public let firewall: Int

        enum CodingKeys: String, CodingKey { case firewall }

        public init(firewall: Int) {
            self.firewall = firewall
        }
    }

    public struct PublicNetSelection: Encodable, Sendable, Equatable {
        public let enableIPv4: Bool
        public let enableIPv6: Bool

        enum CodingKeys: String, CodingKey {
            case enableIPv4 = "enable_ipv4"
            case enableIPv6 = "enable_ipv6"
        }

        public init(enableIPv4: Bool, enableIPv6: Bool) {
            self.enableIPv4 = enableIPv4
            self.enableIPv6 = enableIPv6
        }
    }
}

/// Decoded response of `POST /servers`:
/// `{"server", "action", "next_actions", "root_password"}`.
///
/// `rootPassword` is a secret — callers must never log or persist it in
/// plaintext; it exists only to be shown to the user once and/or handed to
/// the keychain.
public struct CreateServerResult: Decodable, Sendable, Equatable {
    public let server: Server
    public let action: Action
    public let nextActions: [Action]
    public let rootPassword: String?

    enum CodingKeys: String, CodingKey {
        case server, action
        case nextActions = "next_actions"
        case rootPassword = "root_password"
    }

    public init(server: Server, action: Action, nextActions: [Action], rootPassword: String?) {
        self.server = server
        self.action = action
        self.nextActions = nextActions
        self.rootPassword = rootPassword
    }
}
