import Cocoa
import MetalKit

// Custom MTKView that handles mouse clicks and movements
class ClickableMetalView: MTKView {
    var renderer: Renderer?
    
     override func updateTrackingAreas() {
         super.updateTrackingAreas()
         // Remove old areas to avoid stale rects
         for area in trackingAreas {
             removeTrackingArea(area)
         }
         let newArea = NSTrackingArea(
             rect: bounds,
             options: [.activeInKeyWindow, .mouseMoved, .enabledDuringMouseDrag],
             owner: self,
             userInfo: nil
         )
         addTrackingArea(newArea)
         print("✅ Updated tracking area to rect: \(bounds)")
     }
    
    override func mouseMoved(with event: NSEvent) {
      print("🖱️ Raw event.locationInWindow: \(event.locationInWindow)")
      let location = convert(event.locationInWindow, from: nil)
      print("🖱️ Converted location: \(location)")
      print("📏 View bounds: \(bounds)")
      let viewSize = bounds.size
      if !bounds.contains(location) {
          print("⚠️ Mouse outside view bounds - ignoring")
          return
      }
      print("🎯 ClickableMetalView mouseMoved: \(location) in \(viewSize)")
         renderer?.handleMouseMove(at: location, viewSize: viewSize)
    }
    
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let viewSize = bounds.size
        print("🖱️ ClickableMetalView mouseDown: \(location) in \(viewSize)")
        
        // Check if shift key is held for camera control
        if event.modifierFlags.contains(.shift) {
            renderer?.handleMouseDown(at: location)
        } else {
            renderer?.handleClick(at: location, viewSize: viewSize)
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        print("🎯 ClickableMetalView mouseDragged: \(location)")
        renderer?.handleMouseDragged(at: location)
    }
    
    override func mouseUp(with event: NSEvent) {
        print("🖱️ ClickableMetalView mouseUp")
        renderer?.handleMouseUp()
    }
    
//    override func mouseMoved(with event: NSEvent) {
//        let location = convert(event.locationInWindow, from: nil)
//        let viewSize = bounds.size
//        print("🎯 ClickableMetalView mouseMoved: \(location) in \(viewSize)")
//        renderer?.handleMouseMove(at: location, viewSize: viewSize)
//    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override var canBecomeKeyView: Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        print("🎹 ClickableMetalView keyDown: keyCode=\(event.keyCode)")
        
        switch event.keyCode {
        case 123: // Left arrow
            renderer?.navigateToPreviousFrustum()
        case 124: // Right arrow
            renderer?.navigateToNextFrustum()
        case 125: // Down arrow
            renderer?.navigateToNextFrustum()
        case 126: // Up arrow
            renderer?.navigateToPreviousFrustum()
        case 49: // Spacebar
            renderer?.takeScreenshot()
        case 50: // ` key - test click simulation
            testClickSimulation()
        case 18: // 1 key - test first frustum
            testFrustumClick()
        case 19: // 2 key - debug frustums
            renderer?.debugListFrustums()
        case 20: // 3 key - reset viewport
            renderer?.resetViewport()
        default:
            super.keyDown(with: event)
        }
    }
    
    func testClickSimulation() {
        print("🧪 Testing click simulation at center of screen")
        let viewSize = bounds.size
        let centerPoint = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        print("🎯 Simulating click at: \(centerPoint) in view size: \(viewSize)")
        renderer?.handleClick(at: centerPoint, viewSize: viewSize)
    }
    
    func testFrustumClick() {
        print("🧪 Testing direct frustum navigation")
        renderer?.flyToFrustum(at: 0) // Go to first frustum
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
        
        // Enable mouse move tracking
        window.acceptsMouseMovedEvents = true
        metalView.window?.acceptsMouseMovedEvents = true
        
        // Create a tracking area for the entire view to capture mouse moves
//        let trackingArea = NSTrackingArea(
//            rect: metalView.bounds,
//            options: [.activeInKeyWindow, .mouseMoved, .enabledDuringMouseDrag],
//            owner: metalView,
//            userInfo: nil
//        )
//        metalView.addTrackingArea(trackingArea)
        
        // Make the window key and order front
        window.makeKeyAndOrderFront(nil)
        
        // Make the metal view the first responder to receive keyboard events
        window.makeFirstResponder(metalView)
        
        print("✅ Metal Cityscape window created and displayed")
        print("📊 Window size: \(window.frame.size)")
        print("📊 MetalView size: \(metalView.bounds.size)")
        print("📊 Number of frustums: \(renderer.cameraFrustums.count)")
        print("🎹 First responder: \(window.firstResponder)")
        print("🎹 Metal view accepts first responder: \(metalView.acceptsFirstResponder)")
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
