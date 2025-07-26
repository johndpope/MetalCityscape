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

struct CameraFrustum {
    var position: SIMD3<Float>
    var rotation: SIMD3<Float>
    var size: Float
    var photoTexture: MTLTexture?
    var boundingSphere: BoundingSphere
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
    var texturePipelineState: MTLRenderPipelineState!
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
    
    var zoomTarget: SIMD3<Float>?
    var zoomStart: SIMD3<Float>?
    var zoomProgress: Float = 0
    var isZooming = false
    
    init?(metalKitView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.textureLoader = MTKTextureLoader(device: device)
        
        metalKitView.device = device
        metalKitView.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1.0)
        metalKitView.depthStencilPixelFormat = .depth32Float
        
        super.init()
        
        metalKitView.delegate = self
        
        setupPipelines()
        setupDepthStencilState()
        loadCityModel()
        setupScene()
        loadTextures()
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
        texturePipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        texturePipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        texturePipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        texturePipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        texturePipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        texturePipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        texturePipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        wireframePipelineState = try! device.makeRenderPipelineState(descriptor: wireframePipelineDescriptor)
        texturePipelineState = try! device.makeRenderPipelineState(descriptor: texturePipelineDescriptor)
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
        
        // Create 15 camera frustums with random positions
        for _ in 0..<15 {
            let x = Float.random(in: -20...20)
            let z = Float.random(in: -20...20)
            let y = Float.random(in: 2...8)
            let rotX = Float.random(in: -0.3...0.3)
            let rotY = Float.random(in: 0...2 * .pi)
            let rotZ = Float.random(in: -0.2...0.2)
            
            let frustum = CameraFrustum(
                position: [x, y, z],
                rotation: [rotX, rotY, rotZ],
                size: Float.random(in: 1.2...2.0),
                photoTexture: nil,
                boundingSphere: BoundingSphere(center: [x, y, z], radius: 2.0)
            )
            cameraFrustums.append(frustum)
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
        
        updateCamera()
        
        let aspect = Float(view.drawableSize.width / view.drawableSize.height)
        let viewMatrix = camera.viewMatrix()
        let projectionMatrix = camera.projectionMatrix(aspect: aspect)
        
        // Render city model with wireframe
        if let cityMesh = cityMesh {
            renderEncoder.setRenderPipelineState(wireframePipelineState)
            
            let modelMatrix = matrix4x4_scale(0.1, 0.1, 0.1) // Scale down the city model
            var uniforms = Uniforms(modelMatrix: modelMatrix, viewMatrix: viewMatrix, projectionMatrix: projectionMatrix)
            renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            
            for vertexBuffer in cityMesh.vertexBuffers {
                renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: 0)
            }
            
            for submesh in cityMesh.submeshes {
                renderEncoder.drawIndexedPrimitives(
                    type: .line,
                    indexCount: submesh.indexCount,
                    indexType: submesh.indexType,
                    indexBuffer: submesh.indexBuffer.buffer,
                    indexBufferOffset: submesh.indexBuffer.offset
                )
            }
        }
        
        // Render photo quads (textured)
        renderEncoder.setRenderPipelineState(texturePipelineState)
        renderEncoder.setVertexBuffer(photoQuadVertexBuffer, offset: 0, index: 0)
        
        for frustum in cameraFrustums {
            let rotationMatrix = matrix4x4_rotation(radians: frustum.rotation.y, axis: [0, 1, 0]) *
                                 matrix4x4_rotation(radians: frustum.rotation.x, axis: [1, 0, 0]) *
                                 matrix4x4_rotation(radians: frustum.rotation.z, axis: [0, 0, 1])
            
            let modelMatrix = matrix4x4_translation(frustum.position.x, frustum.position.y, frustum.position.z) *
                              rotationMatrix *
                              matrix4x4_scale(frustum.size, frustum.size, frustum.size)
            
            var uniforms = Uniforms(modelMatrix: modelMatrix, viewMatrix: viewMatrix, projectionMatrix: projectionMatrix)
            renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            
            if let texture = frustum.photoTexture {
                renderEncoder.setFragmentTexture(texture, index: 0)
            }
            
            renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: 6, indexType: .uint16, indexBuffer: photoQuadIndexBuffer, indexBufferOffset: 0)
        }
        
        // Render photo borders (wireframe)
        renderEncoder.setRenderPipelineState(wireframePipelineState)
        renderEncoder.setVertexBuffer(photoBorderVertexBuffer, offset: 0, index: 0)
        
        for frustum in cameraFrustums {
            let rotationMatrix = matrix4x4_rotation(radians: frustum.rotation.y, axis: [0, 1, 0]) *
                                 matrix4x4_rotation(radians: frustum.rotation.x, axis: [1, 0, 0]) *
                                 matrix4x4_rotation(radians: frustum.rotation.z, axis: [0, 0, 1])
            
            let modelMatrix = matrix4x4_translation(frustum.position.x, frustum.position.y, frustum.position.z) *
                              rotationMatrix *
                              matrix4x4_scale(frustum.size, frustum.size, frustum.size)
            
            var uniforms = Uniforms(modelMatrix: modelMatrix, viewMatrix: viewMatrix, projectionMatrix: projectionMatrix)
            renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            renderEncoder.drawIndexedPrimitives(type: .line, indexCount: 8, indexType: .uint16, indexBuffer: photoBorderIndexBuffer, indexBufferOffset: 0)
        }
        
        renderEncoder.endEncoding()
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }
    
    func updateCamera() {
        if isZooming, let target = zoomTarget, let start = zoomStart {
            zoomProgress += 0.02
            if zoomProgress >= 1 {
                zoomProgress = 1
                isZooming = false
            }
            
            let t = smoothstep(0, 1, zoomProgress)
            camera.position = mix(start, target, t: t)
            camera.target = mix(camera.target, target - [0, 0, 2], t: t)
        }
    }
    
    func handleClick(at location: CGPoint, viewSize: CGSize) {
        let aspect = Float(viewSize.width / viewSize.height)
        let projMatrix = camera.projectionMatrix(aspect: aspect)
        let viewMatrix = camera.viewMatrix()
        
        let ndcX = (2 * Float(location.x) / Float(viewSize.width)) - 1
        let ndcY = 1 - (2 * Float(location.y) / Float(viewSize.height))
        
        let clipCoords = SIMD4<Float>(ndcX, ndcY, -1, 1)
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
            zoomStart = camera.position
            zoomTarget = frustum.position + normalize(camera.position - frustum.position) * 4
            zoomProgress = 0
            isZooming = true
        }
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