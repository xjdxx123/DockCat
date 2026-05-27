import Foundation

struct Money: Codable, Equatable, Hashable {
    let amount: Decimal
    let currency: String

    func formattedDisplay() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let amountString = formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        switch currency {
        case "USD": return "$\(amountString)"
        case "CNY": return "¥\(amountString)"
        default:    return "\(currency) \(amountString)"
        }
    }
}
