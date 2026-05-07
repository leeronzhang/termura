// Typed harness-level error split out of `RemoteServerHarness.swift`
// so that file stays under the file_length budget. Conforms to
// LocalizedError per CLAUDE.md §5.4 — the iCloud account-status copy
// is what users see if `start()` rejects on a Mac that isn't signed
// into iCloud.

import Foundation
import TermuraRemoteProtocol

enum RemoteHarnessError: Error, Sendable, Equatable {
    case iCloudUnavailable(status: ICloudAccountStatus)
}

extension RemoteHarnessError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .iCloudUnavailable(status):
            switch status {
            case .available:
                "iCloud account check returned an unexpected state."
            case .noAccount:
                "Sign into iCloud in System Settings to use cross-network remote control."
            case .restricted:
                "iCloud is restricted on this device. Adjust Screen Time / MDM settings or use LAN-only mode."
            case .temporarilyUnavailable:
                "iCloud is temporarily unavailable. Check your network and try again."
            case .couldNotDetermine:
                "Couldn't determine iCloud account status. Confirm you're signed in and try again."
            }
        }
    }
}
