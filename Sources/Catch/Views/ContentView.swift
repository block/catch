import AppKit
import SwiftUI

struct ContentView: View {
    let isTestBuild: Bool
    let keyboardMonitorEnabled: Bool

    init(isTestBuild: Bool = false, keyboardMonitorEnabled: Bool = true) {
        self.isTestBuild = isTestBuild
        self.keyboardMonitorEnabled = keyboardMonitorEnabled
    }

    var body: some View {
        VStack(spacing: 0) {
            if isTestBuild {
                Text("TEST BUILD")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.orange)
            }

            SessionCreationConceptView(keyboardMonitorEnabled: keyboardMonitorEnabled)
        }
    }
}
