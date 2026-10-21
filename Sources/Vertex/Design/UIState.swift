import Combine
import Foundation

/// Lightweight observable value used as a stand-in for `@State`.
/// The SwiftUI macro plugin is not available with the Command Line Tools,
/// so local view state is backed by an ObservableObject instead.
final class UIState<Value>: ObservableObject {
    @Published var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
