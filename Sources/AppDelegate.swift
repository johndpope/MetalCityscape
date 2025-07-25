import Cocoa
import MetalKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var window: NSWindow!
    var viewController: ViewController!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create window programmatically
        window = NSWindow(
            contentRect: NSRect(x: 196, y: 240, width: 1024, height: 768),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Metal Cityscape"
        window.titlebarAppearsTransparent = true
        window.center()
        
        // Create Metal view
        let metalView = MTKView(frame: window.contentView!.bounds)
        metalView.autoresizingMask = [.width, .height]
        
        // Create view controller
        viewController = ViewController()
        viewController.view = metalView
        
        // Set window content
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)
        
        // Activate app
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}