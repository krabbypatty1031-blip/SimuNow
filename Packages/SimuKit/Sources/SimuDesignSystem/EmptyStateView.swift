import SwiftUI

public struct EmptyStateView: View {
    private let title: String
    private let symbol: String
    private let message: String

    public init(_ title: String, symbol: String, message: String) {
        self.title = title
        self.symbol = symbol
        self.message = message
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        }
    }
}
