import Foundation

enum CaffeineFormat {
    static func milligrams(_ value: Double) -> String {
        "\(Int(value.rounded())) mg"
    }

    static func compactMilligrams(_ value: Double) -> String {
        "\(Int(value.rounded()))mg"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func range(_ forecast: CaffeineForecast) -> String {
        let low = min(forecast.fasterEstimate, forecast.slowerEstimate)
        let high = max(forecast.fasterEstimate, forecast.slowerEstimate)
        return "\(Int(low.rounded()))-\(Int(high.rounded())) mg"
    }

    static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(Int((interval / 60).rounded()), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }
}
