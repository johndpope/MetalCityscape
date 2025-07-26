import Metal
import MetalKit
import ModelIO
import simd

struct Vertex {
    var position: SIMD3<Float>
    var texCoord: SIMD2<Float>
}

struct Uniforms {
    var modelMatrix: matrix_float4x4
    var viewMatrix: matrix_float4x4
    var projectionMatrix: matrix_float4x4
}

struct UniformsWithColor {
    var modelMatrix: matrix_float4x4
    var viewMatrix: matrix_float4x4
    var projectionMatrix: matrix_float4x4
    var color: SIMD4<Float>
}

struct UniformsWithAlpha {
    var modelMatrix: matrix_float4x4
    var viewMatrix: matrix_float4x4
    var projectionMatrix: matrix_float4x4
    var alpha: Float
}

struct CameraFrustum {
    var position: SIMD3<Float>
    var rotation: SIMD3<Float>
    var size: Float
    var photoTexture: MTLTexture?
    var boundingSphere: BoundingSphere
    var isHovered: Bool = false
}

struct BoundingSphere {
    var center: SIMD3<Float>
    var radius: Float
}

struct Ray {
    var origin: SIMD3<Float>
    var direction: SIMD3<Float>
}

struct Camera {
    var position: SIMD3<Float> = [0, 5, 15]
    var target: SIMD3<Float> = [0, 0, 0]
    var up: SIMD3<Float> = [0, 1, 0]
    var fov: Float = 60 * .pi / 180
    var near: Float = 0.1
    var far: Float = 1000
    
    func viewMatrix() -> matrix_float4x4 {
        return matrix_look_at_left_hand(eye: position, target: target, up: up)
    }
    
    func projectionMatrix(aspect: Float) -> matrix_float4x4 {
        return matrix_perspective_left_hand(fovyRadians: fov, aspectRatio: aspect, nearZ: near, farZ: far)
    }
}

class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var wireframePipelineState: MTLRenderPipelineState!
    var coloredWireframePipelineState: MTLRenderPipelineState!
    var texturePipelineState: MTLRenderPipelineState!
    var transparentTexturePipelineState: MTLRenderPipelineState!
    var depthStencilState: MTLDepthStencilState!
    
    var cityMesh: MTKMesh?
    var cityTexture: MTLTexture?
    var photoQuadVertexBuffer: MTLBuffer!
    var photoQuadIndexBuffer: MTLBuffer!
    var photoBorderVertexBuffer: MTLBuffer!
    var photoBorderIndexBuffer: MTLBuffer!
    
    var cameraFrustums: [CameraFrustum] = []
    var camera = Camera()
    var textureLoader: MTKTextureLoader!
    
    // Enhanced camera animation system
    var flyToStartPosition: SIMD3<Float>?
    var flyToTargetPosition: SIMD3<Float>?
    var flyToStartTarget: SIMD3<Float>?
    var flyToTargetTarget: SIMD3<Float>?
    var flyToProgress: Float = 0
    var isFlyingTo = false
    var flyToDuration: Float = 2.0 // 2 second smooth animation
    
    var hoveredFrustumIndex: Int? = nil
    var currentFrustumIndex: Int = 0
    var viewportFrustumIndex: Int? = nil // Index of frustum currently filling viewport (should be hidden)
    var lastMousePosition: CGPoint = .zero
    var time: Float = 0
    var currentViewportSize: CGSize = .zero
    
    // Mouse drag controls
    var isDragging = false
    var dragStartPosition: CGPoint = .zero
    var cameraStartPosition: SIMD3<Float> = [0, 0, 0]
    var cameraStartTarget: SIMD3<Float> = [0, 0, 0]
    
    init?(metalKitView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice() else { 
            print("❌ Failed to create Metal device")
            return nil 
        }
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.textureLoader = MTKTextureLoader(device: device)
        
        metalKitView.device = device
        metalKitView.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1.0)
        metalKitView.depthStencilPixelFormat = .depth32Float
        
        super.init()
        
        metalKitView.delegate = self
        
        print("✅ Metal device created: \(device.name)")
        
        setupPipelines()
        setupDepthStencilState()
        loadCityModel()
        setupScene()
        loadTextures()
        
        print("✅ Renderer initialized with \(cameraFrustums.count) photo frustums")
        print("🎯 First frustum at: \(cameraFrustums.first?.position ?? SIMD3<Float>(0,0,0))")
        print("🎯 Camera position: \(camera.position)")
        print("🎯 Camera target: \(camera.target)")
    }
    
    func setupPipelines() {
        let library = device.makeDefaultLibrary()!
        
        let wireframeVertexFunction = library.makeFunction(name: "wireframeVertexShader")!
        let wireframeFragmentFunction = library.makeFunction(name: "wireframeFragmentShader")!
        
        let textureVertexFunction = library.makeFunction(name: "textureVertexShader")!
        let textureFragmentFunction = library.makeFunction(name: "textureFragmentShader")!
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.size
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        
        let wireframePipelineDescriptor = MTLRenderPipelineDescriptor()
        wireframePipelineDescriptor.vertexFunction = wireframeVertexFunction
        wireframePipelineDescriptor.fragmentFunction = wireframeFragmentFunction
        wireframePipelineDescriptor.vertexDescriptor = vertexDescriptor
        wireframePipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        wireframePipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        
        let texturePipelineDescriptor = MTLRenderPipelineDescriptor()
        texturePipelineDescriptor.vertexFunction = textureVertexFunction
        texturePipelineDescriptor.fragmentFunction = textureFragmentFunction
        texturePipelineDescriptor.vertexDescriptor = vertexDescriptor
        texturePipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        texturePipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        // Enable alpha blending for texture transparency
        texturePipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        texturePipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        texturePipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        texturePipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        texturePipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        texturePipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        texturePipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        // Create colored wireframe pipeline for hover highlighting
        let coloredWireframeVertexFunction = library.makeFunction(name: "coloredWireframeVertexShader")!
        let coloredWireframeFragmentFunction = library.makeFunction(name: "coloredWireframeFragmentShader")!
        
        let coloredWireframePipelineDescriptor = MTLRenderPipelineDescriptor()
        coloredWireframePipelineDescriptor.vertexFunction = coloredWireframeVertexFunction
        coloredWireframePipelineDescriptor.fragmentFunction = coloredWireframeFragmentFunction
        coloredWireframePipelineDescriptor.vertexDescriptor = vertexDescriptor
        coloredWireframePipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        coloredWireframePipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        
        // Enable alpha blending for transparency
        coloredWireframePipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        coloredWireframePipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        coloredWireframePipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        coloredWireframePipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        coloredWireframePipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        coloredWireframePipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        coloredWireframePipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        // Create transparent texture pipeline
        let transparentTextureVertexFunction = library.makeFunction(name: "transparentTextureVertexShader")!
        let transparentTextureFragmentFunction = library.makeFunction(name: "transparentTextureFragmentShader")!
        
        let transparentTexturePipelineDescriptor = MTLRenderPipelineDescriptor()
        transparentTexturePipelineDescriptor.vertexFunction = transparentTextureVertexFunction
        transparentTexturePipelineDescriptor.fragmentFunction = transparentTextureFragmentFunction
        transparentTexturePipelineDescriptor.vertexDescriptor = vertexDescriptor
        transparentTexturePipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        transparentTexturePipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        
        // Enable alpha blending for transparent textures
        transparentTexturePipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        transparentTexturePipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        transparentTexturePipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        transparentTexturePipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        transparentTexturePipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        transparentTexturePipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        transparentTexturePipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        wireframePipelineState = try! device.makeRenderPipelineState(descriptor: wireframePipelineDescriptor)
        coloredWireframePipelineState = try! device.makeRenderPipelineState(descriptor: coloredWireframePipelineDescriptor)
        texturePipelineState = try! device.makeRenderPipelineState(descriptor: texturePipelineDescriptor)
        transparentTexturePipelineState = try! device.makeRenderPipelineState(descriptor: transparentTexturePipelineDescriptor)
    }
    
    func setupDepthStencilState() {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
    }
    
    func loadCityModel() {
        // Try to load from bundle first, then fall back to absolute path
        var modelURL: URL?
        
        if let bundlePath = Bundle.main.path(forResource: "uploads_files_2720101_BusGameMap", ofType: "obj") {
            modelURL = URL(fileURLWithPath: bundlePath)
        } else {
            // Fallback to absolute path
            let fallbackPath = "/Users/johndpope/Documents/GitHub/Game/96-uploads_files_2720101_textures-2/uploads_files_2720101_BusGameMap.obj"
            if FileManager.default.fileExists(atPath: fallbackPath) {
                modelURL = URL(fileURLWithPath: fallbackPath)
            }
        }
        
        guard let url = modelURL else {
            print("Could not find city model file")
            return
        }
        
        let allocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: allocator)
        
        do {
            let meshes = try MTKMesh.newMeshes(asset: asset, device: device)
            if let firstMesh = meshes.metalKitMeshes.first {
                cityMesh = firstMesh
                print("Successfully loaded city model with \(firstMesh.vertexCount) vertices")
            }
        } catch {
            print("Failed to load city model: \(error)")
        }
    }
    
    func setupScene() {
        createPhotoQuadGeometry()
        createPhotoBorderGeometry()
        
        // Create 15 camera frustums with random positions but aligned horizontally
        for i in 0..<15 {
            let x = Float.random(in: -20...20)
            let z = Float.random(in: -20...20)
            let y = Float.random(in: 2...8)
            let rotX: Float = 0  // No pitch rotation - keep horizontal
            let rotY = Float.random(in: 0...2 * .pi)  // Only yaw rotation for direction
            let rotZ: Float = 0  // No roll rotation - keep level
            
            let frustum = CameraFrustum(
                position: [x, y, z],
                rotation: [rotX, rotY, rotZ],
                size: Float.random(in: 1.2...2.0),
                photoTexture: nil,
                boundingSphere: BoundingSphere(center: [x, y, z], radius: 5.0) // Increased radius for easier picking
            )
            cameraFrustums.append(frustum)
            print("📦 Created frustum \(i): position=\(frustum.position), radius=\(frustum.boundingSphere.radius)")
        }
    }
    
    func createPhotoQuadGeometry() {
        let photoVertices: [Vertex] = [
            Vertex(position: [-0.8, -0.6, -1.8], texCoord: [0, 1]),
            Vertex(position: [ 0.8, -0.6, -1.8], texCoord: [1, 1]),
            Vertex(position: [-0.8,  0.6, -1.8], texCoord: [0, 0]),
            Vertex(position: [ 0.8,  0.6, -1.8], texCoord: [1, 0])
        ]
        
        let photoIndices: [UInt16] = [0, 1, 2, 2, 1, 3]
        
        photoQuadVertexBuffer = device.makeBuffer(bytes: photoVertices, length: MemoryLayout<Vertex>.stride * photoVertices.count, options: [])
        photoQuadIndexBuffer = device.makeBuffer(bytes: photoIndices, length: MemoryLayout<UInt16>.stride * photoIndices.count, options: [])
    }
    
    func createPhotoBorderGeometry() {
        let borderVertices: [Vertex] = [
            // Border frame around the photo (slightly larger)
            Vertex(position: [-0.85, -0.65, -1.79], texCoord: [0, 0]),
            Vertex(position: [ 0.85, -0.65, -1.79], texCoord: [0, 0]),
            Vertex(position: [ 0.85,  0.65, -1.79], texCoord: [0, 0]),
            Vertex(position: [-0.85,  0.65, -1.79], texCoord: [0, 0])
        ]
        
        let borderIndices: [UInt16] = [0, 1, 1, 2, 2, 3, 3, 0]  // Line loop
        
        photoBorderVertexBuffer = device.makeBuffer(bytes: borderVertices, length: MemoryLayout<Vertex>.stride * borderVertices.count, options: [])
        photoBorderIndexBuffer = device.makeBuffer(bytes: borderIndices, length: MemoryLayout<UInt16>.stride * borderIndices.count, options: [])
    }
    
    func loadTextures() {
        let textureOptions: [MTKTextureLoader.Option : Any] = [
            .generateMipmaps : true,
            .SRGB : false
        ]
        
        let texturePath = "/Users/johndpope/Documents/GitHub/Game/96-uploads_files_2720101_textures-2/textures"
        
        // Load a city texture first
        let cityTexturePath = "\(texturePath)/Building_texture10.jpg"
        if FileManager.default.fileExists(atPath: cityTexturePath) {
            if let texture = try? textureLoader.newTexture(URL: URL(fileURLWithPath: cityTexturePath), options: textureOptions) {
                cityTexture = texture
                print("✅ Loaded city texture: Building_texture10.jpg")
            }
        }
        let photoFiles = [
            "download (1).jpg", "download (2).jpg", "download (3).jpg", "download (4).jpg",
            "download (5).jpg", "download (6).jpg", "download (7).jpg", "download (8).jpg",
            "images (1).jpg", "images (2).jpg", "images (3).jpg", "images (4).jpg",
            "images (5).jpg", "images (6).jpg", "images (7).jpg", "images (8).jpg",
            "images (9).jpg", "images (10).jpg", "images (11).jpg", "images (12).jpg"
        ]
        
        for (index, _) in cameraFrustums.enumerated() {
            let fileName = photoFiles[index % photoFiles.count]
            let fullPath = "\(texturePath)/\(fileName)"
            
            if FileManager.default.fileExists(atPath: fullPath) {
                if let texture = try? textureLoader.newTexture(URL: URL(fileURLWithPath: fullPath), options: textureOptions) {
                    cameraFrustums[index].photoTexture = texture
                }
            }
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        
        renderEncoder.setDepthStencilState(depthStencilState)
        
        // Update viewport size
        currentViewportSize = view.bounds.size
        
        // Update time for animation effects
        time += 1.0/60.0 // Assuming 60 FPS
        
        updateCamera()
        
        let aspect = Float(view.drawableSize.width / view.drawableSize.height)
        let viewMatrix = camera.viewMatrix()
        let projectionMatrix = camera.projectionMatrix(aspect: aspect)
        
        // Render city model with textures
        if let cityMesh = cityMesh {
            renderEncoder.setRenderPipelineState(texturePipelineState)
            
            let modelMatrix = matrix4x4_scale(0.5, 0.5, 0.5) // Scale to half size
            var uniforms = Uniforms(modelMatrix: modelMatrix, viewMatrix: viewMatrix, projectionMatrix: projectionMatrix)
            renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            
            // Set a default city texture or color
            if let cityTexture = cityTexture {
                renderEncoder.setFragmentTexture(cityTexture, index: 0)
            }
            
            for vertexBuffer in cityMesh.vertexBuffers {
                renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: 0)
            }
            
            for submesh in cityMesh.submeshes {
                renderEncoder.drawIndexedPrimitives(
                    type: .triangle,  // Use triangles for solid rendering
                    indexCount: submesh.indexCount,
                    indexType: submesh.indexType,
                    indexBuffer: submesh.indexBuffer.buffer,
                    indexBufferOffset: submesh.indexBuffer.offset
                )
            }
        }
        
        // Render photo quads (textured with transparency)
        renderEncoder.setRenderPipelineState(transparentTexturePipelineState)
        renderEncoder.setVertexBuffer(photoQuadVertexBuffer, offset: 0, index: 0)
        
        for frustum in cameraFrustums {
            let rotationMatrix = matrix4x4_rotation(radians: frustum.rotation.y, axis: [0, 1, 0]) *
                                 matrix4x4_rotation(radians: frustum.rotation.x, axis: [1, 0, 0]) *
                                 matrix4x4_rotation(radians: frustum.rotation.z, axis: [0, 0, 1])
            
            let modelMatrix = matrix4x4_translation(frustum.position.x, frustum.position.y, frustum.position.z) *
                              rotationMatrix *
                              matrix4x4_scale(frustum.size, frustum.size, frustum.size)
            
            var uniformsWithAlpha = UniformsWithAlpha(
                modelMatrix: modelMatrix, 
                viewMatrix: viewMatrix, 
                projectionMatrix: projectionMatrix,
                alpha: 0.3 // 30% opacity for transparency
            )
            renderEncoder.setVertexBytes(&uniformsWithAlpha, length: MemoryLayout<UniformsWithAlpha>.stride, index: 1)
            renderEncoder.setFragmentBytes(&uniformsWithAlpha, length: MemoryLayout<UniformsWithAlpha>.stride, index: 1)
            
            if let texture = frustum.photoTexture {
                renderEncoder.setFragmentTexture(texture, index: 0)
            }
            
            renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: 6, indexType: .uint16, indexBuffer: photoQuadIndexBuffer, indexBufferOffset: 0)
        }
        
        // Render photo borders with hover highlighting
        renderEncoder.setVertexBuffer(photoBorderVertexBuffer, offset: 0, index: 0)
        
        let hoveredCount = cameraFrustums.filter { $0.isHovered }.count
        if hoveredCount > 0 {
            print("🔥 Rendering \(hoveredCount) hovered frustums")
        }
        
        for (index, frustum) in cameraFrustums.enumerated() {
            let rotationMatrix = matrix4x4_rotation(radians: frustum.rotation.y, axis: [0, 1, 0]) *
                                 matrix4x4_rotation(radians: frustum.rotation.x, axis: [1, 0, 0]) *
                                 matrix4x4_rotation(radians: frustum.rotation.z, axis: [0, 0, 1])
            
            let modelMatrix = matrix4x4_translation(frustum.position.x, frustum.position.y, frustum.position.z) *
                              rotationMatrix *
                              matrix4x4_scale(frustum.size, frustum.size, frustum.size)
            
            if frustum.isHovered {
                // Use colored wireframe shader for hovered frustum with bold red color
                print("🔴 Rendering hovered frustum \(index) with bold red color")
                renderEncoder.setRenderPipelineState(coloredWireframePipelineState)
                var coloredUniforms = UniformsWithColor(
                    modelMatrix: modelMatrix,
                    viewMatrix: viewMatrix,
                    projectionMatrix: projectionMatrix,
                    color: SIMD4<Float>(1.0, 0.0, 0.0, time) // Bold red with time for pulsing
                )
                renderEncoder.setVertexBytes(&coloredUniforms, length: MemoryLayout<UniformsWithColor>.stride, index: 1)
                renderEncoder.setFragmentBytes(&coloredUniforms, length: MemoryLayout<UniformsWithColor>.stride, index: 1)
            } else {
                // Use normal wireframe shader for non-hovered frustums
                renderEncoder.setRenderPipelineState(wireframePipelineState)
                var uniforms = Uniforms(modelMatrix: modelMatrix, viewMatrix: viewMatrix, projectionMatrix: projectionMatrix)
                renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            }
            
            renderEncoder.drawIndexedPrimitives(type: .line, indexCount: 8, indexType: .uint16, indexBuffer: photoBorderIndexBuffer, indexBufferOffset: 0)
        }
        
        renderEncoder.endEncoding()
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }
    
    func updateCamera() {
        if isFlyingTo, 
           let startPos = flyToStartPosition,
           let targetPos = flyToTargetPosition,
           let startTarget = flyToStartTarget,
           let targetTarget = flyToTargetTarget {
            
            // Smooth fly-to animation with easing
            flyToProgress += 1.0/60.0 / flyToDuration // Assuming 60 FPS
            if flyToProgress >= 1 {
                flyToProgress = 1
                isFlyingTo = false
            }
            
            // Use smooth easing curve (ease-in-out cubic)
            let t = smoothstep(0, 1, flyToProgress)
            
            // Interpolate both position and target
            camera.position = mix(startPos, targetPos, t: t)
            camera.target = mix(startTarget, targetTarget, t: t)
            
            print("Fly-to progress: \(flyToProgress), pos: \(camera.position), target: \(camera.target)")
        }
    }
    
    func resetViewport() {
        print("🔄 Resetting viewport - showing all frustums")
        viewportFrustumIndex = nil
//        viewportFrustumAlpha = 1.0
        
        // Reset camera to overview position
        camera.position = SIMD3<Float>(0, 10, 15)
//        camera.rotation = SIMD3<Float>(0, 0, 0) // Look straight ahead
        
        // Stop any ongoing fly-to animation
        isFlyingTo = false
    }
    
    func handleMouseMove(at location: CGPoint, viewSize: CGSize) {
        lastMousePosition = location
        print("🖱️ Mouse moved to: \(location) in view size: \(viewSize)")
        
        let aspect = Float(viewSize.width / viewSize.height)
        let projMatrix = camera.projectionMatrix(aspect: aspect)
        let viewMatrix = camera.viewMatrix()
        
        // Test different coordinate systems
        let ndcX = (2 * Float(location.x) / Float(viewSize.width)) - 1
        let ndcY = (2 * Float(location.y) / Float(viewSize.height)) - 1
        let ndcY_flipped = 1 - (2 * Float(location.y) / Float(viewSize.height))
        
        print("📍 NDC - Current: (\(ndcX), \(ndcY))")
        print("📍 NDC - Flipped: (\(ndcX), \(ndcY_flipped))")
        print("📍 Screen percentage: x=\(Float(location.x)/Float(viewSize.width)*100)%, y=\(Float(location.y)/Float(viewSize.height)*100)%")
        
        let clipCoords = SIMD4<Float>(ndcX, ndcY_flipped, -1, 1)
        let invProjMatrix = projMatrix.inverse
        var eyeCoords = invProjMatrix * clipCoords
        eyeCoords.z = -1
        eyeCoords.w = 0
        
        print("🔍 Eye coords: \(eyeCoords)")
        print("📐 Proj matrix inverse: \(invProjMatrix)")
        
        let invViewMatrix = viewMatrix.inverse
        let worldDir4 = invViewMatrix * eyeCoords
        let worldDir = normalize(SIMD3<Float>(worldDir4.x, worldDir4.y, worldDir4.z))
        let worldOrigin4 = invViewMatrix * SIMD4<Float>(0, 0, 0, 1)
        let worldOrigin = SIMD3<Float>(worldOrigin4.x, worldOrigin4.y, worldOrigin4.z)
        
        let ray = Ray(origin: worldOrigin, direction: worldDir)
        print("🔦 Ray: origin=\(worldOrigin), direction=\(worldDir)")
        print("📷 Camera: pos=\(camera.position), target=\(camera.target)")
        
        // Clear previous hover state
        let previousHoveredIndex = hoveredFrustumIndex
        for i in 0..<cameraFrustums.count {
            cameraFrustums[i].isHovered = false
        }
        hoveredFrustumIndex = nil
        
        // Find the closest intersected frustum for hover
        var closestDistance: Float = .infinity
        var hitCount = 0
        
        print("🔍 Testing intersection with \(cameraFrustums.count) frustums")
        for (index, frustum) in cameraFrustums.enumerated() {
            let sphere = frustum.boundingSphere
            
            // Project frustum center to screen coordinates to see where it should appear
            let worldPos = SIMD4<Float>(sphere.center.x, sphere.center.y, sphere.center.z, 1.0)
            let clipPos = projMatrix * viewMatrix * worldPos
            let ndcPos = SIMD3<Float>(clipPos.x / clipPos.w, clipPos.y / clipPos.w, clipPos.z / clipPos.w)
            let screenX = (ndcPos.x + 1) * Float(viewSize.width) / 2
            let screenY = (ndcPos.y + 1) * Float(viewSize.height) / 2
            let screenY_flipped = (1 - ndcPos.y) * Float(viewSize.height) / 2
            
            print("🌐 Frustum \(index): world=\(sphere.center), radius=\(sphere.radius)")
            print("   📺 Should appear at screen: (\(screenX), \(screenY)) or flipped: (\(screenX), \(screenY_flipped))")
            print("   🖱️ Mouse is at: (\(location.x), \(location.y))")
            
            if let t = intersectRaySphere(ray: ray, sphere: sphere) {
                hitCount += 1
                print("🎯 HIT! Frustum \(index) at distance \(t), position: \(frustum.position)")
                if t < closestDistance {
                    closestDistance = t
                    hoveredFrustumIndex = index
                    print("👆 This is now the closest hit!")
                }
            } else {
                // Calculate distance to sphere center for debugging
                let toCenter = sphere.center - ray.origin
                let distance = length(toCenter)
                print("❌ Miss frustum \(index), distance to center: \(distance)")
            }
        }
        
        print("📊 Ray intersected \(hitCount) frustums, closest index: \(hoveredFrustumIndex ?? -1)")
        
        // Set hover state for the closest frustum
        if let hoveredIndex = hoveredFrustumIndex {
            cameraFrustums[hoveredIndex].isHovered = true
            print("✨ NOW HOVERING FRUSTUM \(hoveredIndex) - isHovered=\(cameraFrustums[hoveredIndex].isHovered)")
            if hoveredIndex != previousHoveredIndex {
                print("🔄 Hover changed from \(previousHoveredIndex ?? -1) to \(hoveredIndex)")
            }
        } else if previousHoveredIndex != nil {
            print("❌ No longer hovering any frustum (was \(previousHoveredIndex!))")
        }
    }
    
    func handleClick(at location: CGPoint, viewSize: CGSize) {
        let aspect = Float(viewSize.width / viewSize.height)
        let projMatrix = camera.projectionMatrix(aspect: aspect)
        let viewMatrix = camera.viewMatrix()
        
        let ndcX = (2 * Float(location.x) / Float(viewSize.width)) - 1
        let ndcY = (2 * Float(location.y) / Float(viewSize.height)) - 1
        let ndcY_flipped = 1 - (2 * Float(location.y) / Float(viewSize.height))
        
        let clipCoords = SIMD4<Float>(ndcX, ndcY_flipped, -1, 1)
        let invProjMatrix = projMatrix.inverse
        var eyeCoords = invProjMatrix * clipCoords
        eyeCoords.z = -1
        eyeCoords.w = 0
        
        let invViewMatrix = viewMatrix.inverse
        let worldDir4 = invViewMatrix * eyeCoords
        let worldDir = normalize(SIMD3<Float>(worldDir4.x, worldDir4.y, worldDir4.z))
        let worldOrigin4 = invViewMatrix * SIMD4<Float>(0, 0, 0, 1)
        let worldOrigin = SIMD3<Float>(worldOrigin4.x, worldOrigin4.y, worldOrigin4.z)
        
        let ray = Ray(origin: worldOrigin, direction: worldDir)
        
        var closestFrustum: CameraFrustum?
        var closestDistance: Float = .infinity
        
        for frustum in cameraFrustums {
            if let t = intersectRaySphere(ray: ray, sphere: frustum.boundingSphere) {
                if t < closestDistance {
                    closestDistance = t
                    closestFrustum = frustum
                }
            }
        }
        
        if let frustum = closestFrustum {
            // Find the index of this frustum
            if let frustumIndex = cameraFrustums.firstIndex(where: { $0.position == frustum.position }) {
                viewportFrustumIndex = frustumIndex
                print("🎯 Setting frustum \(frustumIndex) as viewport frustum (will be hidden)")
            }
            
            // Calculate camera position to frame the frustum corners in viewport
            let newCameraTarget = calculateFrustumFramingPosition(frustum: frustum, viewportSize: viewSize)
            
            // Start smooth fly-to animation
            flyToStartPosition = camera.position
            flyToTargetPosition = newCameraTarget.position
            flyToStartTarget = camera.target
            flyToTargetTarget = newCameraTarget.target
            flyToProgress = 0
            isFlyingTo = true
            
            print("Starting fly-to animation: \(camera.position) → \(newCameraTarget.position), target: \(camera.target) → \(newCameraTarget.target)")
        }
    }
    
    func calculateFrustumFramingPosition(frustum: CameraFrustum, viewportSize: CGSize) -> (position: SIMD3<Float>, target: SIMD3<Float>) {
        // Get the frustum's world-space corners
        let rotationMatrix = matrix4x4_rotation(radians: frustum.rotation.y, axis: [0, 1, 0]) *
                            matrix4x4_rotation(radians: frustum.rotation.x, axis: [1, 0, 0]) *
                            matrix4x4_rotation(radians: frustum.rotation.z, axis: [0, 0, 1])
        
        let modelMatrix = matrix4x4_translation(frustum.position.x, frustum.position.y, frustum.position.z) *
                         rotationMatrix *
                         matrix4x4_scale(frustum.size, frustum.size, frustum.size)
        
        // Local space corners of the frustum border
        let localCorners: [SIMD4<Float>] = [
            SIMD4<Float>(-0.85, -0.65, -1.79, 1.0), // bottom-left
            SIMD4<Float>( 0.85, -0.65, -1.79, 1.0), // bottom-right
            SIMD4<Float>( 0.85,  0.65, -1.79, 1.0), // top-right
            SIMD4<Float>(-0.85,  0.65, -1.79, 1.0)  // top-left
        ]
        
        // Transform to world space
        let worldCorners = localCorners.map { corner in
            let worldPos = modelMatrix * corner
            return SIMD3<Float>(worldPos.x, worldPos.y, worldPos.z)
        }
        
        // Calculate the center of the frustum for camera target
        let frustumCenter = worldCorners.reduce(SIMD3<Float>(0, 0, 0)) { $0 + $1 } / Float(worldCorners.count)
        
        // Debug: Print world corners
        print("🔍 Frustum world corners:")
        for (i, corner) in worldCorners.enumerated() {
            print("   Corner \(i): \(corner)")
        }
        print("🎯 Frustum center: \(frustumCenter)")
        
        // For horizontally aligned frustums, calculate the normal from the frustum's yaw rotation
        // The frustum faces in its local -Z direction, so we need to rotate that by the yaw
        let frustumYaw = frustum.rotation.y
        let normal = SIMD3<Float>(
            -sin(frustumYaw),  // X component (negative because frustum faces -Z)
            0,                 // No Y component - keep level  
            -cos(frustumYaw)   // Z component (negative because frustum faces -Z)
        )
        
        // For horizontally aligned frustums, we can calculate dimensions more directly
        // Using the local frustum coordinates scaled by the frustum size
        let frustumWidth = 1.7 * frustum.size   // Local width is 2 * 0.85 = 1.7
        let frustumHeight = 1.3 * frustum.size  // Local height is 2 * 0.65 = 1.3
        
        // Get actual viewport aspect ratio
        let viewportAspect = Float(viewportSize.width / viewportSize.height)
        
        // Use camera's actual FOV (60 degrees)
        let fov: Float = 60.0 * .pi / 180.0
        
        // Calculate required distances
        // Vertical FOV is 60 degrees, calculate horizontal FOV from aspect ratio
        let verticalFOV = fov
        let horizontalFOV = 2.0 * atan(tan(verticalFOV / 2.0) * viewportAspect)
        
        // Distance to fit frustum width in horizontal viewport
        let distanceForWidth = (frustumWidth / 2.0) / tan(horizontalFOV / 2.0)
        // Distance to fit frustum height in vertical viewport  
        let distanceForHeight = (frustumHeight / 2.0) / tan(verticalFOV / 2.0)
        
        // Use the larger distance to ensure everything fits exactly (no padding for perfect alignment)
        let requiredDistance = max(distanceForWidth, distanceForHeight)
        
        // Position camera along the normal
        let cameraPosition = frustumCenter + normal * requiredDistance
        
        print("📏 Frustum dimensions: width=\(frustumWidth), height=\(frustumHeight)")
        print("📺 Viewport: \(viewportSize.width)x\(viewportSize.height), aspect=\(viewportAspect)")
        print("📐 Distances: width=\(distanceForWidth), height=\(distanceForHeight), required=\(requiredDistance)")
        print("📍 Camera position: \(cameraPosition) → target: \(frustumCenter)")
        
        return (position: cameraPosition, target: frustumCenter)
    }
    
    func intersectRaySphere(ray: Ray, sphere: BoundingSphere) -> Float? {
        let oc = ray.origin - sphere.center
        let a = dot(ray.direction, ray.direction)
        let b = 2.0 * dot(oc, ray.direction)
        let c = dot(oc, oc) - sphere.radius * sphere.radius
        let discriminant = b * b - 4 * a * c
        
        if discriminant < 0 {
            return nil
        }
        
        let sqrtDiscriminant = sqrt(discriminant)
        let t1 = (-b - sqrtDiscriminant) / (2 * a)
        let t2 = (-b + sqrtDiscriminant) / (2 * a)
        
        if t1 > 0 {
            return t1
        } else if t2 > 0 {
            return t2
        }
        
        return nil
    }
    
    // MARK: - Navigation Methods
    
    func navigateToNextFrustum() {
        guard !cameraFrustums.isEmpty else { return }
        currentFrustumIndex = (currentFrustumIndex + 1) % cameraFrustums.count
        flyToFrustum(at: currentFrustumIndex)
        print("🔄 Navigating to next frustum: \(currentFrustumIndex)")
    }
    
    func navigateToPreviousFrustum() {
        guard !cameraFrustums.isEmpty else { return }
        currentFrustumIndex = currentFrustumIndex == 0 ? cameraFrustums.count - 1 : currentFrustumIndex - 1
        flyToFrustum(at: currentFrustumIndex)
        print("🔄 Navigating to previous frustum: \(currentFrustumIndex)")
    }
    
    func flyToFrustum(at index: Int) {
        guard index >= 0 && index < cameraFrustums.count else { return }
        
        // Set this frustum as the viewport frustum (to be hidden)
        viewportFrustumIndex = index
        print("🎯 Setting frustum \(index) as viewport frustum (will be hidden)")
        
        let frustum = cameraFrustums[index]
        let newCameraTarget = calculateFrustumFramingPosition(frustum: frustum, viewportSize: currentViewportSize)
        
        // Start smooth fly-to animation
        flyToStartPosition = camera.position
        flyToTargetPosition = newCameraTarget.position
        flyToStartTarget = camera.target
        flyToTargetTarget = newCameraTarget.target
        flyToProgress = 0
        isFlyingTo = true
        
        print("🚁 Flying to frustum \(index): \(camera.position) → \(newCameraTarget.position)")
    }
    
    // MARK: - Screenshot Methods
    
    func debugListFrustums() {
        print("🔍 === FRUSTUM DEBUG INFO ===")
        print("📊 Total frustums: \(cameraFrustums.count)")
        print("📊 Current viewport: \(currentViewportSize)")
        print("📊 Camera position: \(camera.position)")
        print("📊 Camera target: \(camera.target)")
        
        for (i, frustum) in cameraFrustums.enumerated() {
            print("🎯 Frustum \(i): pos=\(frustum.position), size=\(frustum.size), hovered=\(frustum.isHovered)")
        }
        print("🔍 === END DEBUG INFO ===")
    }
    
    func handleMouseDown(at location: CGPoint) {
        isDragging = true
        dragStartPosition = location
        cameraStartPosition = camera.position
        cameraStartTarget = camera.target
    }
    
    func handleMouseDragged(at location: CGPoint) {
        guard isDragging else { return }
        
        let deltaX = Float(location.x - dragStartPosition.x) * 0.01
        let deltaY = Float(location.y - dragStartPosition.y) * 0.01
        
        // Calculate rotation around Y axis (horizontal drag)
        let angleY = deltaX
        let rotationY = matrix4x4_rotation(radians: angleY, axis: [0, 1, 0])
        
        // Calculate new camera position by rotating around target
        let offset = cameraStartPosition - cameraStartTarget
        let rotatedOffset4 = rotationY * SIMD4<Float>(offset.x, offset.y, offset.z, 0)
        let rotatedOffset = SIMD3<Float>(rotatedOffset4.x, rotatedOffset4.y, rotatedOffset4.z)
        
        camera.position = cameraStartTarget + rotatedOffset
        
        // Adjust camera height based on vertical drag
        camera.position.y = cameraStartPosition.y - deltaY * 5.0
        camera.position.y = max(1.0, camera.position.y) // Keep camera above ground
    }
    
    func handleMouseUp() {
        isDragging = false
    }
    
    func takeScreenshot() {
        print("📸 Taking screenshot...")
        
        // Create a screenshot filename with timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "MetalCityscape_\(formatter.string(from: Date())).png"
        let desktopPath = NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first!
        let fullPath = "\(desktopPath)/\(fileName)"
        
        // Get the window screenshot
        if let window = NSApplication.shared.mainWindow {
            let windowRect = window.frame
            let cgImage = CGWindowListCreateImage(windowRect, .optionIncludingWindow, CGWindowID(window.windowNumber), .bestResolution)
            
            if let image = cgImage {
                let bitmapRep = NSBitmapImageRep(cgImage: image)
                if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                    do {
                        try pngData.write(to: URL(fileURLWithPath: fullPath))
                        print("✅ Screenshot saved to: \(fullPath)")
                    } catch {
                        print("❌ Failed to save screenshot: \(error)")
                    }
                }
            }
        }
    }
}

func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = clamp((x - edge0) / (edge1 - edge0), min: 0.0, max: 1.0)
    return t * t * (3.0 - 2.0 * t)
}

func clamp(_ value: Float, min: Float, max: Float) -> Float {
    return Swift.max(min, Swift.min(max, value))
}

func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
    return a * (1 - t) + b * t
}
