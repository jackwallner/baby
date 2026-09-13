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
    @State private var isPreparing = false
    @State private var preparationID: UUID?

    var body: some View {
        Group {
            if isPreparing {
                preparingView
            } else if let share {
                CloudSharingController(share: share, container: sharing.ckContainer) { outcome in
                    Task { await complete(outcome) }
                }
                .ignoresSafeArea()
            } else if let errorMessage {
                errorView(message: errorMessage)
            } else {
                explanationView
            }
        }
        .background(AppTheme.paper)
        .presentationDragIndicator(.visible)
        .task(id: preparationID) {
            guard preparationID != nil else { return }
            await prepareShare()
        }
    }

    private func complete(_ outcome: SharingOutcome) async {
        do {
            switch outcome {
            case .saved(let updated): try await sharing.persist(updated, for: child)
            case .stopped: try await sharing.stopped(for: child)
            case .failed:
                share = nil
                errorMessage = "Apple could not save the invitation. Your existing log is safe. Check your connection and try again."
                return
            }
            dismiss()
        } catch {
            share = nil
            errorMessage = "iCloud could not save that sharing change. Your existing log is safe. Check your connection and try again."
        }
    }

    private var explanationView: some View {
        VStack(spacing: AppTheme.spacing) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
                    sharingHeader
                    permissionsCard
                    syncCard
                    Text("You can invite someone or change access later in More.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: AppTheme.contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: AppTheme.tightSpacing) {
                Button {
                    beginSharing()
                } label: {
                    Label(actionTitle, systemImage: actionSymbol)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("sharing.invite")

                Button("Not now") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink2)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("sharing.close")
            }
        }
        .padding(AppTheme.margin)
    }

    private var sharingHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            SharedLogGraphic()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("sharing.graphic")
            Text("One shared log")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text(headerDetail)
                .font(.body)
                .foregroundStyle(AppTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerDetail: String {
        if sharing.share == nil {
            return "Invite your partner to \(child.displayName)'s log. You can both add feeds, diapers and sleep to this same list."
        }
        return "This is \(child.displayName)'s shared log. Review who can access it and keep every update in one place."
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            sharingFact(
                symbol: "eye.fill",
                title: "Who can see it",
                detail: "Only people you invite through Apple can see this baby's log."
            )
            Divider()
            sharingFact(
                symbol: "pencil",
                title: "Who can edit it",
                detail: "Invited people can view, add, edit, and delete entries. The owner manages who has access in Apple's sharing sheet."
            )
        }
        .card()
        .accessibilityIdentifier("sharing.permissions")
    }

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            Label("iCloud sync", systemImage: "icloud.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text("Both phones need to be signed in to iCloud. The first invite needs an internet connection. If a phone is offline, changes wait and may take a little while to appear after it reconnects.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(elevated: true)
        .accessibilityIdentifier("sharing.sync")
    }

    private func sharingFact(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spacing) {
            Image(systemName: symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: AppTheme.graphicSize, height: AppTheme.graphicSize)
                .background(AppTheme.actionFill.opacity(0.45), in: Circle())
                .overlay(Circle().strokeBorder(AppTheme.outline, lineWidth: AppTheme.outlineWidth))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var preparingView: some View {
        VStack(spacing: AppTheme.spacing) {
            ProgressView()
                .tint(AppTheme.accent)
            Text("Preparing your shared log…")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text("Apple's invite sheet will open next.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink2)
                .multilineTextAlignment(.center)
            Button("Cancel") { cancelPreparation() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink2)
                .frame(minHeight: 44)
                .accessibilityIdentifier("sharing.cancel")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.margin)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sharing.preparing")
    }

    private func errorView(message: String) -> some View {
        ScrollView {
            VStack(spacing: AppTheme.looseSpacing) {
                Image(systemName: "icloud.slash")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: AppTheme.welcomeIconSize, height: AppTheme.welcomeIconSize)
                    .background(AppTheme.card, in: AppTheme.cardShape)
                    .graphicBorder()
                    .accessibilityHidden(true)
                Text("Sharing is not ready")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.ink)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: AppTheme.tightSpacing) {
                    Button {
                        beginSharing()
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("sharing.retry")
                    Button("Close") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink2)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("sharing.close")
                }
            }
            .frame(maxWidth: AppTheme.contentWidth)
            .frame(maxWidth: .infinity)
            .padding(AppTheme.margin)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var actionTitle: String {
        guard sharing.share != nil else { return "Invite partner" }
        return sharing.isOwner ? "Manage sharing" : "Sharing settings"
    }

    private var actionSymbol: String {
        guard sharing.share != nil else { return "person.badge.plus" }
        return sharing.isOwner ? "person.2.fill" : "gearshape.2.fill"
    }

    private func beginSharing() {
        guard !isPreparing else { return }
        isPreparing = true
        errorMessage = nil
        preparationID = UUID()
    }

    private func cancelPreparation() {
        preparationID = nil
        isPreparing = false
    }

    private func prepareShare() async {
        do {
            guard try await sharing.ckContainer.accountStatus() == .available else {
                throw SharingPreparationError.iCloudUnavailable
            }
            try Task.checkCancellation()
            let prepared = try await sharing.shareForPresentation(child: child)
            try Task.checkCancellation()
            share = prepared
            isPreparing = false
            preparationID = nil
        } catch is CancellationError {
            // Closing the preparation state cancels the in-flight CloudKit work.
        } catch let error as SharingPreparationError {
            isPreparing = false
            preparationID = nil
            errorMessage = error.message
        } catch {
            isPreparing = false
            preparationID = nil
            errorMessage = "iCloud did not finish preparing this baby's log. Check your connection, wait a moment, then try again. Your existing log is safe."
        }
    }
}

private enum SharingPreparationError: Error {
    case iCloudUnavailable

    var message: String {
        switch self {
        case .iCloudUnavailable:
            "Sign in to iCloud on this iPhone (Settings > your name) before inviting your partner."
        }
    }
}

/// A tiny relationship graphic used wherever sharing needs an object and two
/// people to be understood at a glance.
struct SharedLogGraphic: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        graphicLayout
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You and your partner connected to one shared baby log")
        .accessibilityIdentifier("sharedLogGraphic")
    }

    @ViewBuilder
    private var graphicLayout: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AppTheme.tightSpacing) {
                personBadge(label: "You")
                Image(systemName: "arrow.down")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.ink2)
                    .accessibilityHidden(true)
                notebook
                Image(systemName: "arrow.down")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.ink2)
                    .accessibilityHidden(true)
                personBadge(label: "Partner")
            }
        } else {
            HStack(alignment: .center, spacing: AppTheme.tightSpacing) {
                personBadge(label: "You")
                connector
                notebook
                connector
                personBadge(label: "Partner")
            }
        }
    }

    private var connector: some View {
        Image(systemName: "arrow.left.and.right")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AppTheme.ink2)
            .accessibilityHidden(true)
    }

    private var notebook: some View {
        VStack(spacing: AppTheme.hairSpacing) {
            Image(systemName: "book.closed.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.buttonInk)
            Text("ONE LOG")
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.buttonInk)
                .fixedSize()
        }
        .padding(.horizontal, AppTheme.spacing)
        .padding(.vertical, AppTheme.tightSpacing)
        .background(AppTheme.actionFill, in: AppTheme.cardShape)
        .graphicBorder()
        .accessibilityHidden(true)
    }

    private func personBadge(label: String) -> some View {
        VStack(spacing: AppTheme.hairSpacing) {
            ZStack {
                Circle()
                    .fill(AppTheme.outline)
                    .offset(x: AppTheme.shadowOffset, y: AppTheme.shadowOffset)
                Circle()
                    .fill(AppTheme.card)
                    .overlay(Circle().strokeBorder(AppTheme.outline, lineWidth: AppTheme.outlineWidth))
                Image(systemName: "person.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(width: AppTheme.graphicSize, height: AppTheme.graphicSize)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityHidden(true)
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
