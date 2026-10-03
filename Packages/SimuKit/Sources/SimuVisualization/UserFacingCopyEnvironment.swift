import SwiftUI
import SimuCore

private struct UserFacingCopyKey: EnvironmentKey {
    static let defaultValue = UserFacingCopy.english
}

extension EnvironmentValues {
    public var userFacingCopy: UserFacingCopy {
        get { self[UserFacingCopyKey.self] }
        set { self[UserFacingCopyKey.self] = newValue }
    }
}
