import Foundation

enum Formatters {
    private static var currencyFormatters: [String: NumberFormatter] = [:]
    private static let decimalInputFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter
    }()
    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func currency(_ amount: Decimal, code: String) -> String {
        let formatter = currencyFormatter(for: code.isEmpty ? "USD" : code)
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }

    static func percent(_ rate: Decimal) -> String {
        percentFormatter.string(from: rate as NSDecimalNumber) ?? "\(rate)"
    }

    static func parseDecimal(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let number = decimalInputFormatter.number(from: trimmed) {
            return number.decimalValue
        }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func decimalInput(_ value: Decimal) -> String {
        decimalInputFormatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    private static func currencyFormatter(for code: String) -> NumberFormatter {
        if let formatter = currencyFormatters[code] {
            return formatter
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        currencyFormatters[code] = formatter
        return formatter
    }
}
