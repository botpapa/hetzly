import SafariServices
import SwiftUI

/// `SFSafariViewController` wrapper for opening Hetzner's accounts portal
/// (and any other trusted HTTPS page) in a secure in-app browser. The Safari
/// view controller runs out-of-process: Hetzly never sees the page content,
/// cookies, or credentials — which is the entire point for invoice login.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.barCollapsingEnabled = true

        let controller = SFSafariViewController(url: url, configuration: configuration)
        // iOS 26 deprecates bar/control tinting (it fights the system's
        // glass background effects) — dark override is enough to fit in.
        controller.overrideUserInterfaceStyle = .dark
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

#Preview {
    SafariView(url: URL(string: "https://accounts.hetzner.com/invoice") ?? URL(fileURLWithPath: "/"))
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
}
