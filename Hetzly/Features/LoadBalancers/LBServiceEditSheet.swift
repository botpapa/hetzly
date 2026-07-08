import HetznerKit
import SwiftUI

/// Add/edit sheet for a load balancer service: protocol segmented control,
/// listen/destination ports (monospaced), sticky-sessions + redirect-HTTP
/// toggles for http(s), and a health-check disclosure
/// (interval/timeout/retries + path for http checks).
struct LBServiceEditSheet: View {
    var existingService: LBService?
    var onSave: (LBService) -> Void
    var onCancel: () -> Void

    @State private var serviceProtocol: LBServiceProtocol
    @State private var listenPortText: String
    @State private var destinationPortText: String
    @State private var stickySessions: Bool
    @State private var redirectHTTP: Bool
    @State private var isHealthCheckExpanded = false
    @State private var healthIntervalText: String
    @State private var healthTimeoutText: String
    @State private var healthRetriesText: String
    @State private var healthPath: String

    init(existingService: LBService?, onSave: @escaping (LBService) -> Void, onCancel: @escaping () -> Void) {
        self.existingService = existingService
        self.onSave = onSave
        self.onCancel = onCancel
        _serviceProtocol = State(initialValue: existingService?.protocol ?? .http)
        _listenPortText = State(initialValue: existingService.map { String($0.listenPort) } ?? "")
        _destinationPortText = State(initialValue: existingService.map { String($0.destinationPort) } ?? "")
        _stickySessions = State(initialValue: existingService?.http?.stickySessions ?? false)
        _redirectHTTP = State(initialValue: existingService?.http?.redirectHTTP ?? false)
        _healthIntervalText = State(initialValue: String(existingService?.healthCheck?.interval ?? 15))
        _healthTimeoutText = State(initialValue: String(existingService?.healthCheck?.timeout ?? 10))
        _healthRetriesText = State(initialValue: String(existingService?.healthCheck?.retries ?? 3))
        _healthPath = State(initialValue: existingService?.healthCheck?.http?.path ?? "/")
    }

    private var isEditing: Bool { existingService != nil }

    private var listenPort: Int? { validPort(listenPortText) }
    private var destinationPort: Int? { validPort(destinationPortText) }

    private var canSave: Bool {
        listenPort != nil && destinationPort != nil
            && Int(healthIntervalText) != nil && Int(healthTimeoutText) != nil && Int(healthRetriesText) != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 7) {
                        protocolSection
                        portsSection
                        if serviceProtocol.isHTTPLike { httpSection }
                        healthCheckSection
                    }
                    .padding(Spacing.screenMargin)
                }
            }
            .navigationTitle(isEditing ? "Edit Service" : "New Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
        }
    }

    private var protocolSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Protocol")
            InlineSegmentedPicker(
                options: LBServiceProtocol.editableCases,
                selection: $serviceProtocol,
                label: \.displayName
            )
            // A service's listen port identifies it on the wire; editing
            // keeps it fixed so "update" can't silently become "create".
            .disabled(isEditing)
            .opacity(isEditing ? 0.5 : 1)
        }
    }

    private var portsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Ports")
            GlassCard {
                VStack(spacing: Spacing.unit * 3) {
                    portField(title: "Listen", text: $listenPortText, disabled: isEditing)
                    Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                    portField(title: "Destination", text: $destinationPortText, disabled: false)
                }
            }
            if isEditing {
                Text("The listen port identifies this service and can't be changed.").caption()
            }
        }
    }

    private func portField(title: String, text: Binding<String>, disabled: Bool) -> some View {
        HStack {
            Text(title).bodySecondary()
            Spacer()
            TextField("443", text: text)
                .textFieldStyle(.plain)
                .keyboardType(.numberPad)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
                .disabled(disabled)
                .opacity(disabled ? 0.5 : 1)
        }
    }

    private var httpSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("HTTP")
            GlassCard {
                VStack(spacing: Spacing.unit * 3) {
                    Toggle("Sticky sessions", isOn: $stickySessions)
                        .tint(HetzlyColors.accent)
                        .foregroundStyle(HetzlyColors.textPrimary)
                    Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                    Toggle("Redirect HTTP → HTTPS", isOn: $redirectHTTP)
                        .tint(HetzlyColors.accent)
                        .foregroundStyle(HetzlyColors.textPrimary)
                        .disabled(serviceProtocol != .https)
                        .opacity(serviceProtocol == .https ? 1 : 0.5)
                }
            }
        }
    }

    private var healthCheckSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            DisclosureGroup(isExpanded: $isHealthCheckExpanded) {
                GlassCard {
                    VStack(spacing: Spacing.unit * 3) {
                        numberField(title: "Interval (s)", text: $healthIntervalText)
                        Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                        numberField(title: "Timeout (s)", text: $healthTimeoutText)
                        Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                        numberField(title: "Retries", text: $healthRetriesText)
                        if serviceProtocol.isHTTPLike {
                            Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                            HStack {
                                Text("Path").bodySecondary()
                                Spacer()
                                TextField("/healthz", text: $healthPath)
                                    .textFieldStyle(.plain)
                                    .font(.system(.body, design: .monospaced))
                                    .multilineTextAlignment(.trailing)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                        }
                    }
                }
                .padding(.top, Spacing.unit * 2)
            } label: {
                SectionLabel("Health Check")
            }
            .tint(HetzlyColors.textTertiary)
        }
    }

    private func numberField(title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title).bodySecondary()
            Spacer()
            TextField("0", text: text)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
        }
    }

    private func validPort(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)), (1...65_535).contains(value) else {
            return nil
        }
        return value
    }

    private func save() {
        guard let listenPort, let destinationPort else { return }
        let interval = Int(healthIntervalText) ?? 15
        let timeout = Int(healthTimeoutText) ?? 10
        let retries = Int(healthRetriesText) ?? 3

        let http: LBServiceHTTP? = serviceProtocol.isHTTPLike
            ? LBServiceHTTP(
                cookieName: existingService?.http?.cookieName,
                cookieLifetime: existingService?.http?.cookieLifetime,
                certificates: existingService?.http?.certificates ?? [],
                redirectHTTP: serviceProtocol == .https ? redirectHTTP : nil,
                stickySessions: stickySessions
            )
            : nil

        let healthHTTP: LBHealthCheckHTTP? = serviceProtocol.isHTTPLike
            ? LBHealthCheckHTTP(
                domain: existingService?.healthCheck?.http?.domain,
                path: healthPath.isEmpty ? "/" : healthPath,
                response: nil,
                statusCodes: nil,
                tls: serviceProtocol == .https
            )
            : nil

        let service = LBService(
            protocol: serviceProtocol,
            listenPort: listenPort,
            destinationPort: destinationPort,
            proxyprotocol: existingService?.proxyprotocol ?? false,
            http: http,
            healthCheck: LBHealthCheck(
                protocol: serviceProtocol.isHTTPLike ? .http : .tcp,
                port: destinationPort,
                interval: interval,
                timeout: timeout,
                retries: retries,
                http: healthHTTP
            )
        )
        onSave(service)
    }
}

#Preview("New service") {
    LBServiceEditSheet(existingService: nil, onSave: { _ in }, onCancel: {})
        .preferredColorScheme(.dark)
}

#Preview("Edit service") {
    LBServiceEditSheet(existingService: LBPreviewFixtures.httpsService, onSave: { _ in }, onCancel: {})
        .preferredColorScheme(.dark)
}
