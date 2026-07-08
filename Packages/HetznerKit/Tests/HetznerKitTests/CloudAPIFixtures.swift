import Foundation

/// Realistic Hetzner Cloud API JSON fixtures shared across `CloudAPI*Tests`.
enum CloudAPIFixtures {
    /// A single `server_type` object, embedded shape (as it appears nested
    /// inside a server) — includes `prices`, matching real API responses.
    static func serverTypeJSON(id: Int = 22, name: String = "cx22") -> String {
        """
        {
            "id": \(id),
            "name": "\(name)",
            "description": "\(name.uppercased())",
            "cores": 2,
            "memory": 4.0,
            "disk": 40,
            "cpu_type": "shared",
            "architecture": "x86",
            "deprecated": false,
            "prices": [
                {
                    "location": "fsn1",
                    "price_hourly": {"net": "0.0060", "gross": "0.006426"},
                    "price_monthly": {"net": "3.9200", "gross": "4.194400"}
                }
            ]
        }
        """
    }

    static let datacenterJSON = """
    {
        "id": 1,
        "name": "fsn1-dc14",
        "description": "Falkenstein 1 DC14",
        "location": {
            "id": 1,
            "name": "fsn1",
            "description": "Falkenstein DC Park 1",
            "country": "DE",
            "city": "Falkenstein",
            "latitude": 50.47612,
            "longitude": 12.370071,
            "network_zone": "eu-central"
        }
    }
    """

    /// A full realistic server object body (not wrapped in an envelope).
    static func serverJSON(id: Int = 42, name: String = "web-01", status: String = "running") -> String {
        """
        {
            "id": \(id),
            "name": "\(name)",
            "status": "\(status)",
            "created": "2016-01-30T23:50:00+00:00",
            "public_net": {
                "ipv4": {"ip": "1.2.3.4"},
                "ipv6": {"ip": "2001:db8::/64"}
            },
            "server_type": \(serverTypeJSON()),
            "datacenter": \(datacenterJSON),
            "labels": {"env": "prod"},
            "locked": false,
            "protection": {"delete": false, "rebuild": false},
            "backup_window": null,
            "rescue_enabled": false,
            "primary_disk_size": 40,
            "included_traffic": 21990232555520,
            "outgoing_traffic": 123456,
            "ingoing_traffic": null
        }
        """
    }

    static func serverEnvelopeJSON(id: Int = 42, name: String = "web-01", status: String = "running") -> Data {
        Data("{\"server\": \(serverJSON(id: id, name: name, status: status))}".utf8)
    }

    static func serversPageJSON(servers: [(id: Int, name: String)], nextPage: Int?) -> Data {
        let items = servers.map { serverJSON(id: $0.id, name: $0.name) }.joined(separator: ",")
        let nextString = nextPage.map(String.init) ?? "null"
        let json = """
        {
            "servers": [\(items)],
            "meta": {
                "pagination": {
                    "page": 1, "per_page": 50, "previous_page": null,
                    "next_page": \(nextString), "last_page": 2, "total_entries": \(servers.count)
                }
            }
        }
        """
        return Data(json.utf8)
    }

    static func actionJSON(
        id: Int = 1,
        command: String = "poweron",
        status: String = "running",
        progress: Int = 50,
        finished: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) -> String {
        let finishedValue = finished.map { "\"\($0)\"" } ?? "null"
        let errorValue: String
        if let errorCode, let errorMessage {
            errorValue = "{\"code\": \"\(errorCode)\", \"message\": \"\(errorMessage)\"}"
        } else {
            errorValue = "null"
        }
        return """
        {
            "id": \(id),
            "command": "\(command)",
            "status": "\(status)",
            "progress": \(progress),
            "started": "2016-01-30T23:50:00+00:00",
            "finished": \(finishedValue),
            "resources": [{"id": 42, "type": "server"}],
            "error": \(errorValue)
        }
        """
    }

    static func actionEnvelopeJSON(
        id: Int = 1,
        command: String = "poweron",
        status: String = "running",
        progress: Int = 50,
        finished: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) -> Data {
        Data(
            "{\"action\": \(actionJSON(id: id, command: command, status: status, progress: progress, finished: finished, errorCode: errorCode, errorMessage: errorMessage))}"
                .utf8
        )
    }

    /// Metrics fixture with one malformed value pair (non-numeric string
    /// value) and one entirely malformed row (non-numeric timestamp) mixed
    /// into an otherwise-valid `cpu` series, plus a well-formed
    /// `network.0.bandwidth.in` series.
    static let metricsJSON: Data = {
        let json = """
        {
            "metrics": {
                "start": "2016-01-30T23:50:00Z",
                "end": "2016-01-30T23:55:00Z",
                "step": 60,
                "time_series": {
                    "cpu": {
                        "values": [
                            [1454198400.0, "42.5"],
                            [1454198460.0, "not-a-number"],
                            ["bad-timestamp", "1"],
                            [1454198520.0, 55]
                        ]
                    },
                    "network.0.bandwidth.in": {
                        "values": [
                            [1454198400.0, "100"]
                        ]
                    }
                }
            }
        }
        """
        return Data(json.utf8)
    }()

    static let pricingJSON = Data(
        """
        {
            "pricing": {
                "currency": "EUR",
                "vat_rate": "19.00",
                "server_types": [
                    {
                        "id": 22,
                        "name": "cx22",
                        "prices": [
                            {
                                "location": "fsn1",
                                "price_hourly": {"net": "0.0060", "gross": "0.006426"},
                                "price_monthly": {"net": "3.9200", "gross": "4.194400"}
                            }
                        ]
                    }
                ],
                "primary_ips": [
                    {
                        "type": "ipv4",
                        "prices": [
                            {
                                "location": "fsn1",
                                "price_hourly": {"net": "0.0010", "gross": "0.00119"},
                                "price_monthly": {"net": "0.5000", "gross": "0.595000"}
                            }
                        ]
                    }
                ],
                "volume": {
                    "price_per_gb_month": {"net": "0.0400", "gross": "0.047600"}
                },
                "server_backup": {"percentage": "20.00"}
            }
        }
        """.utf8
    )
}
