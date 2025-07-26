import Cocoa
import MetalKit

class ViewController: NSViewController {
    
    var renderer: Renderer!
    var mtkView: MTKView!
    
    override func loadView() {
        // Create a basic view - will be replaced with MTKView by AppDelegate
        view = NSView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let mtkView = self.view as? MTKView else {
            print("View attached to ViewController is not an MTKView")
            return
        }
        
        self.mtkView = mtkView
        
        guard let renderer = Renderer(metalKitView: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }
        
        self.renderer = renderer
        mtkView.preferredFramesPerSecond = 60
    }
    
    override func mouseDown(with event: NSEvent) {
        let location = view.convert(event.locationInWindow, from: nil)
        let viewSize = view.bounds.size
        print("🖱️ ViewController mouseDown called: \(location) in \(viewSize)")
        renderer?.handleClick(at: location, viewSize: viewSize)
    }
    
    override func mouseMoved(with event: NSEvent) {
        let location = view.convert(event.locationInWindow, from: nil)
        let viewSize = view.bounds.size
        print("🎯 ViewController mouseMoved called: \(location) in \(viewSize)")
        renderer?.handleMouseMove(at: location, viewSize: viewSize)
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        // Enable mouse move tracking
        view.window?.acceptsMouseMovedEvents = true
        
        // Make this view the first responder to receive mouse events
        view.window?.makeFirstResponder(self)
        
        print("✅ ViewController: View appeared, mouse tracking enabled")
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
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
        default:
            super.keyDown(with: event)
        }
    }
}