import CloudKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Logging together. The owner shows a code (or sends its link); the other
/// person scans it with their Camera and their taps land in the same log.
/// Apple's sheet is kept only for the part it is good at: seeing who is in,
/// removing someone, and stopping or leaving.
struct SharingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sharing: SharingService
    let child: Child

    @State private var share: CKShare?
    @State private var errorMessage: String?
    @State private var isPreparing = false
    @State private var preparationID: UUID?
    @State private var showManage = false

    var body: some View {
        NavigationStack {
            Group {
                if isPreparing {
                    preparingView
                } else if let errorMessage {
                    errorView(message: errorMessage)
                } else if let share, !sharing.isOwner {
                    ParticipantView(child: child, ownerName: sharing.ownerName, manage: { showManage = true })
                } else if let url = share?.url ?? Self.previewInviteURL {
                    InviteView(child: child, url: url, joined: sharing.participantNames, manage: { showManage = true })
                } else {
                    explanationView
                }
            }
            .background(AppTheme.paper)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("sharing.close")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showManage) {
            if let share {
                CloudSharingController(share: share, container: sharing.ckContainer) { outcome in
                    Task { await complete(outcome) }
                }
                .ignoresSafeArea()
            }
        }
        .task {
            // An existing share goes straight to its code.
            if sharing.share != nil, share == nil, errorMessage == nil { beginSharing() }
        }
        .task(id: preparationID) {
            guard preparationID != nil else { return }
            await prepareShare()
        }
    }

    #if DEBUG
    /// `-SharingPreview` renders the invite screen without iCloud, for captures.
    private static var previewInviteURL: URL? {
        ProcessInfo.processInfo.arguments.contains("-SharingPreview") ? URL(string: "https://www.icloud.com/share/0PreviewInviteLinkForCaptures#Nora") : nil
    }
    #else
    private static let previewInviteURL: URL? = nil
    #endif

    private func complete(_ outcome: SharingOutcome) async {
        showManage = false
        do {
            switch outcome {
            case .saved(let updated):
                try await sharing.persist(updated, for: child)
                share = updated
            case .stopped:
                try await sharing.stopped(for: child)
                dismiss()
            case .failed:
                errorMessage = "Apple could not save that change. Your existing log is safe. Check your connection and try again."
            }
        } catch {
            errorMessage = "iCloud could not save that sharing change. Your existing log is safe. Check your connection and try again."
        }
    }

    private var explanationView: some View {
        VStack(spacing: AppTheme.spacing) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
                    VStack(alignment: .leading, spacing: AppTheme.spacing) {
                        SharedLogGraphic()
                            .accessibilityIdentifier("sharing.graphic")
                        Text("Log together")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                        Text("Invite your partner, a grandparent or a nanny. Everyone logs from their own iPhone into \(child.displayName)'s log, and every phone shows the latest feed.")
                            .font(.body)
                            .foregroundStyle(AppTheme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    JoinSteps(child: child)
                    AccessNote()
                }
                .frame(maxWidth: AppTheme.contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button {
                beginSharing()
            } label: {
                Label("Create invite", systemImage: "qrcode")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("sharing.invite")
        }
        .padding(AppTheme.margin)
    }

    private var preparingView: some View {
        VStack(spacing: AppTheme.spacing) {
            ProgressView()
                .tint(AppTheme.accent)
            Text("Making your invite…")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text("This takes a few seconds the first time.")
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
                Button {
                    beginSharing()
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("sharing.retry")
            }
            .frame(maxWidth: AppTheme.contentWidth)
            .frame(maxWidth: .infinity)
            .padding(AppTheme.margin)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollBounceBehavior(.basedOnSize)
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
            let prepared = sharing.isSharedChild(child)
                ? try await sharing.shareForPresentation(child: child)
                : try await sharing.inviteShare(child: child)
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
            "Sign in to iCloud on this iPhone (Settings > your name) before inviting anyone."
        }
    }
}

/// The owner's invite: a code to scan in the room, a link to send from afar,
/// and who has already joined.
private struct InviteView: View {
    let child: Child
    let url: URL
    let joined: [String]
    let manage: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.spacing) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
                    Text("Invite to \(child.displayName)'s log")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    codeCard
                    JoinSteps(child: child)
                    joinedCard
                    AccessNote()
                }
                .frame(maxWidth: AppTheme.contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: AppTheme.tightSpacing) {
                ShareLink(
                    item: url,
                    subject: Text("Join \(child.displayName)'s log"),
                    message: Text("Join \(child.displayName)'s log in Baby Tracker so we can both log feeds, diapers and sleep.")
                ) {
                    Label("Send invite link", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("sharing.sendLink")
                Button("Manage people", action: manage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("sharing.manage")
            }
        }
        .padding(AppTheme.margin)
    }

    private var codeCard: some View {
        VStack(spacing: AppTheme.spacing) {
            if let image = InviteCode.image(for: url) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: AppTheme.inviteCodeSize, height: AppTheme.inviteCodeSize)
                    .padding(AppTheme.spacing)
                    .background(Color.white, in: AppTheme.cardShape)
                    .accessibilityLabel("Invite code")
                    .accessibilityIdentifier("sharing.code")
            }
            Text("Scan with the other iPhone's Camera")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private var joinedCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            SectionLabel(text: "Logging together")
            if joined.isEmpty {
                Text("No one has joined yet. Once they scan the code, their name appears here.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(joined, id: \.self) { name in
                    Label(name, systemImage: "person.fill.checkmark")
                        .font(.body.weight(.medium))
                        .foregroundStyle(AppTheme.ink)
                }
            }
        }
        .card(elevated: true)
        .accessibilityIdentifier("sharing.joined")
    }
}

/// Someone who joined a log they did not start.
private struct ParticipantView: View {
    let child: Child
    let ownerName: String?
    let manage: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.spacing) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
                    SharedLogGraphic()
                    Text("You're logging together")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    Text("Everything you log for \(child.displayName) shows up on \(ownerName ?? "their")\(ownerName == nil ? "" : "'s") phone, and everything they log shows up here.")
                        .font(.body)
                        .foregroundStyle(AppTheme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    AccessNote(isOwner: false)
                }
                .frame(maxWidth: AppTheme.contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            Button("People and leaving", action: manage)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("sharing.manage")
        }
        .padding(AppTheme.margin)
    }
}

/// The three steps, written for the person holding the other phone.
struct JoinSteps: View {
    let child: Child?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            step(1, "They install Baby Tracker", "On their own iPhone. It's free.")
            step(2, "They scan your code", "With their Camera app, or by opening the link you send.")
            step(3, "You both log", "Feeds, diapers and sleep from either phone land in \(child.map { "\($0.displayName)'s" } ?? "the same") log.")
        }
        .card()
        .accessibilityIdentifier("sharing.steps")
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spacing) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(AppTheme.buttonInk)
                .frame(width: AppTheme.iconSize, height: AppTheme.iconSize)
                .background(AppTheme.actionFill, in: Circle())
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
        .accessibilityElement(children: .combine)
    }
}

private struct AccessNote: View {
    var isOwner = true

    var body: some View {
        Label {
            Text(isOwner
                 ? "Anyone with your code or link can join and edit this log, so share it only with people you trust. Remove someone or stop sharing in Manage people. Both phones need iCloud; an offline phone catches up when it reconnects."
                 : "You can add, edit and delete entries. An offline phone catches up when it reconnects.")
                .font(.footnote)
                .foregroundStyle(AppTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.fill")
                .font(.footnote)
                .foregroundStyle(AppTheme.ink2)
        }
        .accessibilityIdentifier("sharing.access")
    }
}

enum InviteCode {
    static func image(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Joining from the second phone when the Camera route isn't handy: paste
/// the link. Scanning or tapping the link skips this screen entirely.
struct JoinSharedLogView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sharing: SharingService
    @EnvironmentObject private var events: EventStore
    @State private var link = ""
    @State private var phase = Phase.idle

    enum Phase: Equatable {
        case idle
        case joining
        case joined
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.spacing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
                        Text("Join a shared log")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                        Text("Use this when someone else already started the log. You'll both log into the same baby.")
                            .font(.body)
                            .foregroundStyle(AppTheme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        scanCard
                        pasteCard
                    }
                    .frame(maxWidth: AppTheme.contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)

                statusView
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    Task { await join() }
                } label: {
                    if phase == .joining {
                        ProgressView().tint(AppTheme.buttonInk)
                    } else {
                        Text("Join log")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || phase == .joining || phase == .joined)
                .accessibilityIdentifier("join.submit")
            }
            .padding(AppTheme.margin)
            .background(AppTheme.paper)
            .tint(AppTheme.accent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("join.close")
                }
            }
        }
        .onChange(of: events.child?.objectID) { _, _ in
            if phase == .joined, let child = events.child, sharing.isSharedChild(child) { dismiss() }
        }
    }

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            Label("Easiest: scan their code", systemImage: "camera.viewfinder")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text("On their phone: More, then Invite someone. Point this iPhone's Camera app at the code and tap the banner. Baby Tracker opens and joins.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
        .accessibilityIdentifier("join.scan")
    }

    private var pasteCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            Label("Or paste the link they sent", systemImage: "link")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            TextField("icloud.com/share/…", text: $link, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .frame(minHeight: 44)
                .accessibilityIdentifier("join.link")
            PasteButton(payloadType: String.self) { strings in
                if let pasted = strings.first { link = pasted }
            }
            .buttonBorderShape(.capsule)
        }
        .card(elevated: true)
    }

    @ViewBuilder
    private var statusView: some View {
        switch phase {
        case .idle, .joining:
            EmptyView()
        case .joined:
            Label("You're in. The log is on its way to this phone.", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .accessibilityIdentifier("join.joined")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(AppTheme.notice)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("join.error")
        }
    }

    private func join() async {
        phase = .joining
        do {
            try await sharing.join(pasted: link)
            phase = .joined
            Haptics.logged()
        } catch let error as SharingService.JoinError {
            phase = .failed(error.message)
            Haptics.failed()
        } catch {
            phase = .failed(SharingService.JoinError.unavailable.message)
            Haptics.failed()
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
        .accessibilityLabel("You and another caregiver logging into one shared baby log")
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
                    .fill(AppTheme.shadow)
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
        // Matches the invite link: anyone holding it joins with edit rights.
        controller.availablePermissions = [.allowPublic, .allowReadWrite]
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
