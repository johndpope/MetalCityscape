import Cocoa
import MetalKit

class ViewController: NSViewController {
    
    var renderer: Renderer!
    var mtkView: MTKView!
    
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
        renderer.handleClick(at: location, viewSize: viewSize)
    }
}