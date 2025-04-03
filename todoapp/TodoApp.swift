import SwiftUI

@main
struct TodoApp: App {
    @Environment(\.scenePhase) var scenePhase
    
    var content = ContentView()
    var body: some Scene {
        WindowGroup {
            self.content
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background, .inactive:
                print(".\(phase)")
                Bridge.updateActiveState(false)
            case .active:
                print(".active")
                if !Bridge.isActiveState {
                    Bridge.updateActiveState(true)
                    if let bridge = Bridge.instance {
                        bridge.reinit()
                    }
                }
            @unknown default:
                break
            }
        }
    }
}
