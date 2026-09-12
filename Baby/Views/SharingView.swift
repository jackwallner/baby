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
                CloudSharingController(share: share, container: sharing.ckContainer) { outcome in
                    Task { await complete(outcome) }
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
        .background(AppTheme.paper)
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

    private func complete(_ outcome: SharingOutcome) async {
        do {
            switch outcome {
            case .saved(let updated): try await sharing.persist(updated, for: child)
            case .stopped: try await sharing.stopped(for: child)
            case .failed:
                share = nil
                errorMessage = "The invitation could not be saved. Your baby's log is safe. Check your connection and try again."
                return
            }
            dismiss()
        } catch {
            share = nil
            errorMessage = "iCloud could not save that change. Check your connection and try again."
        }
    }
}

enum SharingOutcome {
    case saved(CKShare)
    case stopped
    case failed
}

struct CloudSharingController: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let finished: (SharingOutcome) -> Void

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(finished: finished, title: share[CKShare.SystemFieldKey.title] as? String) }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let finished: (SharingOutcome) -> Void
        let title: String?

        init(finished: @escaping (SharingOutcome) -> Void, title: String?) {
            self.finished = finished
            self.title = title
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            finished(.failed)
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { title ?? "Baby log" }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            if let share = csc.share { finished(.saved(share)) }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            finished(.stopped)
        }
    }
}
