import SwiftUI

/// About, privacy, and deleting everything.
/// DRAFT: the About and privacy wording here is adapted from the Android text for iPhone and still needs the author's review.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmWipe = false
    @State private var showPrivacy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "About")
                    Text("SomaSense is a free and open source calendar tool for logging symptoms and sensations that are felt across the body. All data entered into the app is stored on this iPhone without being transmitted to the developer or to Apple. You may share your own calendar log to email or other apps on your iPhone by selecting the Share option in the Calendar or Reports tab.")
                    Text("Use SomaSense to track feelings you have across the body over time and to monitor their progression or transience. When noticing any new or unusual pain or symptom, the tool can be used to create a log of a symptom’s progression for sharing with a physician. Please seek immediate care if you have a new symptom you haven’t addressed with your healthcare provider previously.")
                    BodyShapeSection()
                    Text("SomaSense was authored by ncubeeight LLC for distribution on GitHub and the Apple App Store. Visit ncubeeight at [ncubeeight.com](https://ncubeeight.com)")
                    Text("The code on GitHub is open source under the Apache 2.0 license, which lets you use, modify and share it under that license’s terms. If the code base is altered from original form into a new code-fork or integrated into a new app, please attribute [github.com/ncubeeight/SomaSense-iOS](https://github.com/ncubeeight/SomaSense-iOS) source code referring to open source under Apache 2.0 license but clarify how the code has been altered to your own users with your own new Privacy Policy. The original Privacy Policy should not be used for code created by other entities outside of ncubeeight LLC. Please include the reference to MakeHuman license in all derivative code if the body map is integrated into your versions of this app.")
                    Text("SomaSense was coded in Claude Code with supplemental support by Apple Xcode, with additional support by Google Gemini for marketing collateral design.")
                    Text("The body models used in SomaSense are provided by MakeHuman under an open source license available to review here: [MakeHuman license](https://github.com/makehumancommunity/makehuman/blob/master/LICENSE.md)")
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "Your data")
                    Button("Privacy policy") { showPrivacy = true }
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 44)
                        .foregroundStyle(Ink.teal)
                    Text("This removes every report, symptom-free day and body shape setting from this iPhone. It can’t be undone. Anything you already shared isn’t affected.")
                    Button { confirmWipe = true } label: {
                        Text("Delete stored on-device data")
                            .font(.body.bold())
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(Ink.rust)
                            .overlay(Capsule().stroke(Ink.rust, lineWidth: 1))
                    }
                    .confirmationDialog("Delete all stored data?", isPresented: $confirmWipe, titleVisibility: .visible) {
                        Button("Delete everything", role: .destructive) { model.deleteAll() }
                    } message: {
                        Text("Every report, symptom-free day and body shape setting will be removed from this iPhone. This can’t be undone.")
                    }
                }
            }
            .padding(20)
        }
        .tint(Ink.teal)
        .background(Color.white)
        .foregroundStyle(Ink.text)
        .sheet(isPresented: $showPrivacy) { PrivacyView() }
    }
}

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Draft for review").font(.caption.bold()).foregroundStyle(Ink.rust)
                    Link("Full privacy policy", destination: URL(string: "https://ncubeeight.github.io/SomaSense-iOS/privacy/")!)
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 44)
                        .foregroundStyle(Ink.teal)
                    Text("Your log stays on this iPhone unless you choose to share it, and ncubeeight LLC never receives it.")
                    Text("What the app stores").font(.headline)
                    Text("The reports you save (where on the body, when, symptom types, severity, notes, medicines, activities and concerns), the days you mark as symptom-free, and the choices you remove from the lists.")
                    Text("Sharing").font(.headline)
                    Text("The Share buttons on the Calendar and Reports tabs send your information only when you choose to, by email or to the app you pick. Once sent, it’s handled by that app and the people you sent it to, and SomaSense can’t recall it.")
                    Text("Backups").font(.headline)
                    Text("The log is left out of iCloud and computer backups, so it won’t move to a new iPhone. To keep a copy, share your log before changing phones.")
                    Text("Security").font(.headline)
                    Text("The log is encrypted by iOS while your iPhone is locked. SomaSense doesn’t have its own passcode, so anyone who can use your unlocked iPhone can open it.")
                    Text("Deleting your data").font(.headline)
                    Text("You can delete a single report from its detail screen, or everything from Settings. Deleting the app also removes it. Deleted data can’t be restored.")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Privacy policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .foregroundStyle(Ink.text)
    }
}
