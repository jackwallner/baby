import SwiftUI
import VisionKit

/// Joining a log someone else started. The same model drives the Join choice
/// in onboarding and the Join sheet in More, so both behave identically.
@MainActor
final class JoinLogModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case joining
        case joined
        case failed(String)
    }

    @Published var link = ""
    @Published private(set) var phase = Phase.idle

    var canJoin: Bool {
        !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && phase != .joining && phase != .joined
    }

    func join(using sharing: SharingService) async {
        guard canJoin else { return }
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

    /// A scanned code joins straight away; there is nothing left to confirm.
    func scanned(_ payload: String, using sharing: SharingService) async {
        link = payload
        await join(using: sharing)
    }
}

/// How to join, the in-app scanner, and the paste field. The caller places
/// the Join button so onboarding keeps its one fixed bottom action.
struct JoinLogForm: View {
    @EnvironmentObject private var sharing: SharingService
    @ObservedObject var model: JoinLogModel
    @State private var showScanner = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
            scanCard
            pasteCard
            JoinStatus(phase: model.phase)
        }
        .fullScreenCover(isPresented: $showScanner) {
            InviteScannerScreen { payload in
                showScanner = false
                Task { await model.scanned(payload, using: sharing) }
            }
        }
    }

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            Label("Scan their code", systemImage: "qrcode.viewfinder")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text("On their phone: More, then Invite someone. A QR code appears.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if InviteScanner.isAvailable {
                Button {
                    showScanner = true
                } label: {
                    Label("Open scanner", systemImage: "camera.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("join.scan.open")
            } else {
                Text("Point this iPhone's Camera app at the code and tap the Baby Tracker banner.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    private var pasteCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            Label("Or paste the link they sent", systemImage: "link")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            TextField("icloud.com/share/…", text: $model.link, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .frame(minHeight: 44)
                .accessibilityIdentifier("join.link")
            PasteButton(payloadType: String.self) { strings in
                if let pasted = strings.first { model.link = pasted }
            }
            .buttonBorderShape(.capsule)
        }
        .card(elevated: true)
    }
}

struct JoinStatus: View {
    let phase: JoinLogModel.Phase

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .joining:
            Label("Joining…", systemImage: "icloud.and.arrow.down")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink2)
                .accessibilityIdentifier("join.joining")
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
}

/// The Join sheet in More, for someone who already has the app set up.
struct JoinSharedLogView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sharing: SharingService
    @EnvironmentObject private var events: EventStore
    @StateObject private var model = JoinLogModel()

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
                        JoinLogForm(model: model)
                    }
                    .frame(maxWidth: AppTheme.contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)

                JoinButton(model: model)
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
            if model.phase == .joined, let child = events.child, sharing.isSharedChild(child) { dismiss() }
        }
    }
}

struct JoinButton: View {
    @EnvironmentObject private var sharing: SharingService
    @ObservedObject var model: JoinLogModel

    var body: some View {
        Button {
            Task { await model.join(using: sharing) }
        } label: {
            if model.phase == .joining {
                ProgressView().tint(AppTheme.buttonInk)
            } else {
                Text("Join log")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!model.canJoin)
        .opacity(model.canJoin || model.phase == .joining ? 1 : 0.55)
        .accessibilityIdentifier("join.submit")
    }
}

/// Shown instead of onboarding while an accepted invitation's baby is on its
/// way, so a new parent is never left on a setup screen wondering whether the
/// link worked, and never makes a duplicate baby while they wait.
struct JoiningSharedLogView: View {
    @EnvironmentObject private var events: EventStore
    @State private var isTakingLong = false

    var body: some View {
        VStack(spacing: AppTheme.looseSpacing) {
            Spacer(minLength: 0)
            SharedLogGraphic()
            ProgressView()
                .tint(AppTheme.accent)
            VStack(spacing: AppTheme.tightSpacing) {
                Text("Joining the shared log")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text("Bringing the log to this iPhone. It usually takes under a minute; keep Baby Tracker open.")
                    .font(.body)
                    .foregroundStyle(AppTheme.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isTakingLong {
                Text("Still waiting? Check that both phones are online and signed in to iCloud.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if isTakingLong {
                Button("Start my own log instead") { events.stopWaitingForSharedBaby() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("joining.giveUp")
            }
        }
        .frame(maxWidth: AppTheme.contentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.margin)
        .background(AppTheme.paper)
        .task {
            try? await Task.sleep(for: .seconds(ProcessInfo.processInfo.arguments.contains("-FastJoinTimeout") ? 1 : 60))
            isTakingLong = true
        }
    }
}

/// Live camera scanning for the invite QR code, inside the app.
struct InviteScannerScreen: View {
    @Environment(\.dismiss) private var dismiss
    let found: (String) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            InviteScanner(found: found)
                .ignoresSafeArea()
            VStack(spacing: AppTheme.spacing) {
                Text("Point at the code on their phone")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Button("Cancel") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minHeight: 44)
            }
            .padding(AppTheme.looseSpacing)
            .frame(maxWidth: .infinity)
            .background(AppTheme.card, in: AppTheme.cardShape)
            .graphicBorder()
            .padding(AppTheme.margin)
        }
    }
}

struct InviteScanner: UIViewControllerRepresentable {
    let found: (String) -> Void

    @MainActor static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        guard !scanner.isScanning else { return }
        try? scanner.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let found: (String) -> Void
        private var didFind = false

        init(found: @escaping (String) -> Void) {
            self.found = found
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didFind else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue,
                      ShareInvite.url(in: payload) != nil else { continue }
                didFind = true
                dataScanner.stopScanning()
                found(payload)
                return
            }
        }
    }
}
