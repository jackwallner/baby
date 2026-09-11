import SwiftUI

/// The hospital tally sheet, one row per day of life, with the typical range
/// beside each day's count and the "call your pediatrician if" lines under
/// the table. Free, on a fresh install, with or without data.
struct FirstWeeksView: View {
    @EnvironmentObject private var events: EventStore
    @State private var now = Date.now

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
                intro
                if let child = events.child, let birth = child.birthDate {
                    table(birthDate: birth)
                } else {
                    noBirthDate
                }
                callCard
                Text(Guidance.sourceLine)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppTheme.margin)
            .padding(.vertical, AppTheme.spacing)
        }
        .background(AppTheme.paper)
        .navigationTitle("First Weeks")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { now = .now }
    }

    private var intro: some View {
        Text("Wet and dirty diapers per day, next to the typical range for that day of life. The same sheet the hospital sends home, filled in by your taps.")
            .font(.subheadline)
            .foregroundStyle(AppTheme.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var noBirthDate: some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            Text("Typical ranges by day of life")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            ForEach(1...6, id: \.self) { day in
                let range = Guidance.range(forDayOfLife: day)
                HStack {
                    Text(day == 6 ? "Day 6 on" : "Day \(day)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 80, alignment: .leading)
                    Text(range.summary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink2)
                        .monospacedDigit()
                }
            }
            Text("Add your baby's birth date in Settings and this fills in day by day.")
                .font(.footnote)
                .foregroundStyle(AppTheme.ink2)
                .padding(.top, AppTheme.hairSpacing)
        }
        .card()
    }

    private func table(birthDate: Date) -> some View {
        let today = DateHelpers.dayOfLife(birthDate: birthDate, on: now) ?? 0
        return VStack(spacing: 0) {
            header
            ForEach(1...Guidance.tallyDays, id: \.self) { day in
                let date = DateHelpers.date(forDayOfLife: day, birthDate: birthDate)
                let tally = events.tally(on: date, now: now)
                let range = Guidance.range(forDayOfLife: day)
                let state: RowState = day < today ? .past : (day == today ? .today : .future)
                row(day: day, date: date, tally: tally, range: range, state: state)
                if day < Guidance.tallyDays {
                    Divider().overlay(AppTheme.cardElevated)
                }
            }
        }
        .padding(.vertical, AppTheme.tightSpacing)
        .background(AppTheme.card, in: AppTheme.cardShape)
        .accessibilityIdentifier("tallyTable")
    }

    private enum RowState { case past, today, future }

    private var header: some View {
        HStack(spacing: AppTheme.tightSpacing) {
            Text("DAY").frame(width: 44, alignment: .leading)
            Text("WET").frame(maxWidth: .infinity)
            Text("DIRTY").frame(maxWidth: .infinity)
            Text("FEEDS").frame(maxWidth: .infinity)
            Text("TYPICAL").frame(width: 92, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(AppTheme.ink3)
        .padding(.horizontal, AppTheme.looseSpacing)
        .padding(.vertical, AppTheme.tightSpacing)
    }

    private func row(day: Int, date: Date, tally: DayTally, range: Guidance.DayRange, state: RowState) -> some View {
        let dim = state == .future
        return VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
            HStack(spacing: AppTheme.tightSpacing) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(day)")
                        .font(.body.weight(state == .today ? .bold : .medium))
                    Text(date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.ink3)
                }
                .frame(width: 44, alignment: .leading)
                count(dim ? nil : tally.wet, kind: .wet, min: range.wetMin, complete: state == .past)
                count(dim ? nil : tally.dirty, kind: .dirty, min: range.dirtyMin, complete: state == .past)
                count(dim ? nil : tally.feeds, kind: .feed, min: range.feedsMin, complete: state == .past)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(range.wetMin)+ · \(range.dirtyMin)+")
                    Text("\(range.feedsMin) to \(range.feedsMax)")
                }
                .font(.caption)
                .foregroundStyle(AppTheme.ink2)
                .monospacedDigit()
                .frame(width: 92, alignment: .trailing)
            }
            if state == .past, let line = Guidance.comparison(wet: tally.wet, dirty: tally.dirty, day: day, dayComplete: true) {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(AppTheme.notice)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(dim ? AppTheme.ink3 : AppTheme.ink)
        .padding(.horizontal, AppTheme.looseSpacing)
        .padding(.vertical, AppTheme.tightSpacing)
        .background(state == .today ? AppTheme.cardElevated : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Day \(day): \(tally.wet) wet, \(tally.dirty) dirty, \(tally.feeds) feeds. Typical \(range.summary).")
    }

    private func count(_ value: Int?, kind: EventKind, min: Int, complete: Bool) -> some View {
        Text(value.map(String.init) ?? "–")
            .font(.body.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(value == nil ? AppTheme.ink3 : AppTheme.color(for: kind))
            .frame(maxWidth: .infinity)
    }

    private var callCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            Text("Call your pediatrician if")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            ForEach(Guidance.callIf, id: \.self) { line in
                HStack(alignment: .top, spacing: AppTheme.tightSpacing) {
                    Text("•").foregroundStyle(AppTheme.ink3)
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(Guidance.disclaimer)
                .font(.caption)
                .foregroundStyle(AppTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, AppTheme.hairSpacing)
        }
        .card()
        .accessibilityIdentifier("callCard")
    }
}
