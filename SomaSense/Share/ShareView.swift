import MessageUI
import SwiftUI
import UIKit

/// The preview before sharing: the PDF's pages, then Email and Share.
/// Email opens a Mail message with the subject, the text and the files attached.
/// Share opens the iOS share sheet, which also offers other mail apps, Messages and Save to Files.
struct ShareView: View {
    @Environment(\.dismiss) private var dismiss
    let package: SharePackage
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(package.previews.enumerated()), id: \.offset) { n, page in
                            Image(uiImage: page)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .overlay(Rectangle().stroke(Ink.line, lineWidth: 1))
                                .accessibilityLabel("Page \(n + 1) of \(package.previews.count) of the PDF")
                        }
                    }
                    .padding(16)
                }
                .background(Ink.stage)
                VStack(alignment: .leading, spacing: 10) {
                    Text(package.note).font(.footnote).foregroundStyle(Ink.muted)
                    HStack(spacing: 12) {
                        Button { email() } label: {
                            Label("Email", systemImage: "envelope")
                                .font(.body.bold())
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .foregroundStyle(Ink.teal)
                                .overlay(Capsule().stroke(Ink.teal, lineWidth: 1))
                        }
                        Button { share() } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.body.bold())
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .foregroundStyle(.white)
                                .background(Ink.teal, in: Capsule())
                        }
                    }
                }
                .padding(16)
                .background(.white)
            }
            .navigationTitle(package.heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
            .alert(problem ?? "", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
        .foregroundStyle(Ink.text)
    }

    private func email() {
        guard MFMailComposeViewController.canSendMail() else {
            problem = "Mail isn’t set up on this iPhone. Tap Share to send it with another email app."
            return
        }
        let mail = MFMailComposeViewController()
        mail.setSubject(package.subject)
        mail.setMessageBody(package.text, isHTML: false)
        if let png = package.calendar { mail.addAttachmentData(png, mimeType: "image/png", fileName: package.calendarName) }
        mail.addAttachmentData(package.pdf, mimeType: "application/pdf", fileName: package.pdfName)
        let delegate = MailDelegate { result in
            if result == .failed { problem = "The email couldn’t be sent. It may be in your Outbox." }
        }
        mail.mailComposeDelegate = delegate
        objc_setAssociatedObject(mail, &MailDelegate.key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        Presenter.present(mail)
    }

    private func share() {
        guard let files = ShareExport.write(package) else {
            problem = "This could not be prepared for sharing."
            return
        }
        let items: [Any] = [ShareText(subject: package.subject, text: package.text)] + files
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        Presenter.present(sheet)
    }
}

/// The message text, with the subject Mail and other email apps use.
final class ShareText: NSObject, UIActivityItemSource {
    let subject: String
    let text: String

    init(subject: String, text: String) {
        self.subject = subject
        self.text = text
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { text }

    func activityViewController(_ controller: UIActivityViewController, itemForActivityType type: UIActivity.ActivityType?) -> Any? { text }

    func activityViewController(_ controller: UIActivityViewController, subjectForActivityType type: UIActivity.ActivityType?) -> String { subject }
}

/// Mail calls its delegate on the main thread.
@MainActor
final class MailDelegate: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
    nonisolated(unsafe) static var key = 0
    let done: @MainActor (MFMailComposeResult) -> Void

    init(done: @escaping @MainActor (MFMailComposeResult) -> Void) { self.done = done }

    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
        done(result)
    }
}

/// Presents a UIKit screen over whatever is showing, including a SwiftUI sheet.
@MainActor
enum Presenter {
    static func present(_ vc: UIViewController) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        vc.popoverPresentationController?.sourceView = top.view
        top.present(vc, animated: true)
    }
}

/// The outlined Share button at the top of the Calendar and Reports tabs.
struct ShareButton: View {
    var label: String
    var hint: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: "square.and.arrow.up")
                .font(.body.bold())
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .foregroundStyle(Ink.teal)
                .overlay(Capsule().stroke(Ink.teal, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }
}
