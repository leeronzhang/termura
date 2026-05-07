import Foundation
import Security

/// Module-private entitlement probe shared between AppDelegate's launch-time
/// gate and `RemoteServerHarness.assembleIfNeeded`. Returns true when the
/// running process carries an iCloud-services entitlement that includes
/// "CloudKit" or "CloudKit-Anonymous". Debug builds use TermuraDebug.entitlements
/// (no iCloud) so this returns false there; assembling the harness without it
/// would prompt for the paired-devices Keychain item and then trap inside
/// CKContainer.m:748 with "process must have a com.apple.developer.icloud-services
/// entitlement". Bailing early here keeps both side effects off Debug.
func processHasICloudEntitlement() -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    guard let value = SecTaskCopyValueForEntitlement(
        task,
        "com.apple.developer.icloud-services" as CFString,
        nil
    ) else { return false }
    guard let services = value as? [String] else { return false }
    return services.contains("CloudKit") || services.contains("CloudKit-Anonymous")
}
