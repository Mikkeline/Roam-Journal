import SwiftUI
struct PrivacyPolicyScreen: View {
    private var policy: String {
        guard let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "md") else { return "Privacy policy unavailable. Contact the developer." }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "Privacy policy unavailable."
    }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            if let text = Bundle.main.object(forInfoDictionaryKey: "RoamPrivacyPolicyURL") as? String, let url = URL(string: text), url.scheme == "https" { Link("View public privacy policy", destination: url) }
            Text(policy).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.padding() }.navigationTitle("Privacy policy")
    }
}
