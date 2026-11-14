#if os(iOS) || os(macOS)
import ClashClientKit
import ClashClientUI
import Foundation

 
 
 
 
 
 

extension ModuleCertificateError {
    var authoredText: AuthoredText {
        switch self {
         
         
         
         
         
        case .invalidHostname(let host):
            return .app("A certificate can't be made for %@, so modules don't reach it.", arguments: [host])
        case .encryptionFailed, .pkcs12ImportFailed, .noIdentity, .keyRejected, .keychain:
            return .app("The certificate wasn't created; try again.")
        }
    }
}

extension ModuleCertificateError: ClashAuthoredError {
    var displayText: ClashDisplayText { authoredText.displayText }
}

 
 
extension ModuleCertificateUnavailable: ClashAuthoredError {
    var displayText: ClashDisplayText { AuthoredText.app("The certificate wasn't created; try again.").displayText }
}
#endif
