import AppKit
import SwiftUI

struct ContentView: View {
    let isTestBuild: Bool
    let testBuildLabel: String
    let keyboardMonitorEnabled: Bool

    init(isTestBuild: Bool = false, testBuildLabel: String = "TEST BUILD", keyboardMonitorEnabled: Bool = true) {
        self.isTestBuild = isTestBuild
        self.testBuildLabel = testBuildLabel
        self.keyboardMonitorEnabled = keyboardMonitorEnabled
    }

    var body: some View {
        VStack(spacing: 0) {
            if isTestBuild {
                Text(testBuildLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange)
            }

            MainView(keyboardMonitorEnabled: keyboardMonitorEnabled)
        }
    }
}
