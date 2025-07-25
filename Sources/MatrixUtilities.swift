import simd

func matrix4x4_translation(_ x: Float, _ y: Float, _ z: Float) -> matrix_float4x4 {
    var matrix = matrix_identity_float4x4
    matrix.columns.3 = SIMD4<Float>(x, y, z, 1)
    return matrix
}

func matrix4x4_scale(_ sx: Float, _ sy: Float, _ sz: Float) -> matrix_float4x4 {
    var matrix = matrix_identity_float4x4
    matrix.columns.0.x = sx
    matrix.columns.1.y = sy
    matrix.columns.2.z = sz
    return matrix
}

func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    
    var matrix = matrix_identity_float4x4
    
    matrix.columns.0 = SIMD4<Float>(ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0)
    matrix.columns.1 = SIMD4<Float>(x * y * ci - z * st, ct + y * y * ci, z * y * ci + x * st, 0)
    matrix.columns.2 = SIMD4<Float>(x * z * ci + y * st, y * z * ci - x * st, ct + z * z * ci, 0)
    matrix.columns.3 = SIMD4<Float>(0, 0, 0, 1)
    
    return matrix
}

func matrix_perspective_left_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (farZ - nearZ)
    
    var matrix = matrix_float4x4()
    matrix.columns.0 = SIMD4<Float>(xs, 0, 0, 0)
    matrix.columns.1 = SIMD4<Float>(0, ys, 0, 0)
    matrix.columns.2 = SIMD4<Float>(0, 0, zs, 1)
    matrix.columns.3 = SIMD4<Float>(0, 0, -nearZ * zs, 0)
    
    return matrix
}

func matrix_look_at_left_hand(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
    let z = normalize(target - eye)
    let x = normalize(cross(up, z))
    let y = cross(z, x)
    
    var matrix = matrix_identity_float4x4
    matrix.columns.0 = SIMD4<Float>(x.x, y.x, z.x, 0)
    matrix.columns.1 = SIMD4<Float>(x.y, y.y, z.y, 0)
    matrix.columns.2 = SIMD4<Float>(x.z, y.z, z.z, 0)
    matrix.columns.3 = SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
    
    return matrix
}