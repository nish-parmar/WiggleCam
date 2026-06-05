import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("wg.fps") var framesPerSecond: Int = 8
    @AppStorage("wg.filmLook") var filmLookEnabled: Bool = false
    @AppStorage("wg.preferDualCam") var preferDualCamera: Bool = true
}
