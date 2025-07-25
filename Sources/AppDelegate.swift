import Cocoa
import MetalKit

// Custom MTKView that handles mouse clicks
class ClickableMetalView: MTKView {
    var renderer: Renderer?
    
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let viewSize = bounds.size
        renderer?.handleClick(at: location, viewSize: viewSize)
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var window: NSWindow!
    var renderer: Renderer!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create the window programmatically
        let windowStyle: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
            styleMask: windowStyle,
            backing: .buffered,
            defer: false
        )
        
        // Center the window on screen
        window.center()
        
        // Set the title
        window.title = "Metal Cityscape"
        
        // Create Metal view that fills the window
        let metalView = ClickableMetalView(frame: window.contentLayoutRect)
        
        // Initialize renderer with the Metal view
        guard let renderer = Renderer(metalKitView: metalView) else {
            print("❌ Failed to initialize renderer")
            NSApp.terminate(nil)
            return
        }
        self.renderer = renderer
        metalView.renderer = renderer  // Connect for mouse handling
        
        // Set the Metal view as content view
        window.contentView = metalView
        
        // Make the window key and order front
        window.makeKeyAndOrderFront(nil)
        
        print("✅ Metal Cityscape window created and displayed")
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}