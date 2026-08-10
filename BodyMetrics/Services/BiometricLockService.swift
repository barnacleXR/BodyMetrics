import Foundation
import LocalAuthentication

/// 生物识别解锁(系统级 Face ID / Touch ID,失败回退系统密码)
enum BiometricLockService {
    /// 设备是否可评估(生物识别或系统密码任一可用)
    static func canEvaluate() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// 执行验证;返回是否通过
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }

    /// 当前设备生物识别类型名(用于提示)
    static var biometricTypeName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return String(localized: "面容 ID / 触控 ID 解锁")
        }
    }
}
