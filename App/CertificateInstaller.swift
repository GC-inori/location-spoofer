import Foundation
import UIKit

enum CertificateInstaller {
    static func open(url: URL, completion: @escaping (Bool) -> Void) {
        UIApplication.shared.open(url, options: [:], completionHandler: completion)
    }
}
