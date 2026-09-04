import Foundation
import SwiftUI

// Magic, don't touch
_ = FileManager.default
seteuid(501)

MainActor.assumeIsolated {
    RelaxinLiteApp.main()
}
