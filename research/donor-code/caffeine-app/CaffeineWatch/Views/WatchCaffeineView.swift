import SwiftUI

struct WatchCaffeineView: View {
    @EnvironmentObject private var settings: CaffeineSettings
    @StateObject private var health = HealthKitService.shared
    @StateObject private var log = CaffeineLogService.shared
    @State private var preview: DrinkPreset?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(spacing: 1) {
                    Text(CaffeineFormat.milligrams(health.remainingNow))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.cyan)
                    Text("estimated now")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack {
                    Label(CaffeineFormat.time(settings.bedtimeDate), systemImage: "moon.fill")
                    Spacer()
                    Text(CaffeineFormat.compactMilligrams(health.bedtimeForecast.estimatedMilligrams))
                        .fontWeight(.semibold)
                }
                .font(.caption)
                .padding(8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))

                ForEach(settings.quickAddDrinks) { drink in
                    Button {
                        preview = drink
                    } label: {
                        HStack {
                            Image(systemName: drink.symbolName)
                            Text(drink.name)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer()
                            Text(CaffeineFormat.compactMilligrams(drink.milligrams))
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.violet)
                }

                if log.pendingWriteCount > 0 {
                    Text("\(log.pendingWriteCount) waiting to save to Health")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                if let entry = log.lastEntry {
                    Button("Undo \(Int(entry.milligrams)) mg") {
                        Task { _ = await log.undoLast() }
                    }
                    .font(.caption)
                }
            }
        }
        .sheet(item: $preview) { drink in
            WatchDosePreview(drink: drink) { preview = nil }
        }
    }
}

private struct WatchDosePreview: View {
    @EnvironmentObject private var settings: CaffeineSettings
    @StateObject private var health = HealthKitService.shared
    let drink: DrinkPreset
    let dismiss: () -> Void

    private var estimate: Double {
        CaffeineClearance.forecastAdding(
            dose: drink.milligrams,
            at: .now,
            samples: health.recentSamples,
            forecastDate: settings.bedtimeDate,
            selection: settings.sourceSelection,
            halfLifeHours: settings.halfLifeHours
        ).estimatedMilligrams
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: drink.symbolName)
                    .foregroundStyle(Theme.cyan)
                Text(drink.name)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text(CaffeineFormat.milligrams(estimate))
                    .font(.title2.bold())
                Text("estimated at bedtime")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                Button("Log \(Int(drink.milligrams)) mg") {
                    Task {
                        _ = await CaffeineLogService.shared.log(
                            milligrams: drink.milligrams,
                            drinkName: drink.name
                        )
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.violet)
                Button("Cancel", action: dismiss)
                    .font(.caption)
            }
        }
    }
}
