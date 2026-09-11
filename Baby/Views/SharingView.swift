import CloudKit
import SwiftUI
import UIKit

/// Apple's own sharing sheet, wrapped: Messages, Mail, a link. The partner
/// taps the link, iOS opens the app, and the baby appears on their phone.
struct SharingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sharing: SharingService
    let child: Child

    @State private var share: CKShare?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let share {
                CloudSharingController(share: share, container: sharing.ckContainer) { saved in
                    if let saved { sharing.persist(saved, for: child) } else { sharing.stopped(for: child) }
                    dismiss()
                }
                .ignoresSafeArea()
            } else if let errorMessage {
                VStack(spacing: AppTheme.spacing) {
                    Text("Couldn't start sharing")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink2)
                        .multilineTextAlignment(.center)
                    Button("Close") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(AppTheme.margin)
            } else {
                ProgressView("Preparing…")
            }
        }
        .task {
            guard sharing.iCloudAvailable else {
                errorMessage = "Sign in to iCloud on this iPhone (Settings › your name) to share with your partner."
                return
            }
            do {
                share = try await sharing.shareForPresentation(child: child)
            } catch {
                errorMessage = "iCloud did not respond. Check your connection and try again."
            }
        }
    }
}

private struct CloudSharingController: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let finished: (CKShare?) -> Void

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(finished: finished, title: share[CKShare.SystemFieldKey.title] as? String) }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let finished: (CKShare?) -> Void
        let title: String?

        init(finished: @escaping (CKShare?) -> Void, title: String?) {
            self.finished = finished
            self.title = title
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            finished(nil)
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { title ?? "Baby log" }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            finished(csc.share)
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            finished(nil)
        }
    }
}
