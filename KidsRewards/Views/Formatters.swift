import Foundation

enum Formatters {
    static func currency(_ amount: Decimal, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code.isEmpty ? "USD" : code
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }

    static func percent(_ rate: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 2
        return formatter.string(from: rate as NSDecimalNumber) ?? "\(rate)"
    }
}
