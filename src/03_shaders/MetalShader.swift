import Metal
import MetalKit


// Metal 着色器封装类
final class MetalShader {
    // 属性
    let device_: MTLDevice   // GPU设备
    var library_: MTLLibrary? // 当前着色器库（可从字符串更新）


    // 初始化（先置为 nil，之后通过 updateLibrary 传入源码）
    init(device: MTLDevice) {
        self.device_ = device
        print("MetalShader 初始化成功")
    }
    
    // 从源码字符串重新编译着色器库（支持运行时热更新）
    // - 用法与 glShaderSource + glCompileShader 类似
    func updateLibrary(source: String) -> Bool {
        do {
            let newLibrary = try device_.makeLibrary(source: source, options: nil)
            library_ = newLibrary
            print("着色器库编译成功")
            return true
        } catch {
            print("着色器库编译失败: \(error.localizedDescription)")
            return false
        }
    }

    // 提取着色器方法
    func function(name: String) -> MTLFunction? {
        guard let lib = library_ else {
            print("着色器库未初始化，请先调用 updateLibrary")
            return nil
        }
        guard let function = lib.makeFunction(name: name) else {
            print("着色器方法提取失败: \(name)")
            return nil
        }
        return function
    }
    
    // 创建渲染管线
    func makeRenderPipeline(
        vertexFunc: String,
        fragmentFunc: String,
        vertexDescriptor: MTLVertexDescriptor,
        colorPixelFormat: MTLPixelFormat = .bgra8Unorm,
        depthPixelFormat: MTLPixelFormat = .depth32Float
    ) -> MTLRenderPipelineState? {
        
        // 获取着色器方法
        guard let vert = function(name: vertexFunc),
              let frag = function(name: fragmentFunc) else {
            return nil
        }
        
        // 管线描述
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vert
        desc.fragmentFunction = frag
        desc.vertexDescriptor = vertexDescriptor
        
        // 通用像素格式
        desc.colorAttachments[0].pixelFormat = colorPixelFormat
        desc.depthAttachmentPixelFormat = depthPixelFormat

        // 启用 alpha 混合 (透明 PNG 叠加)
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        // 创建管线
        do {
            return try device_.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("渲染管线创建失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    // 创建计算管线
    func makeComputePipeline(kernelFunc: String) -> MTLComputePipelineState? {
        guard let kernel = function(name: kernelFunc) else { return nil }
        
        do {
            return try device_.makeComputePipelineState(function: kernel)
        } catch {
            print("计算管线创建失败: \(error.localizedDescription)")
            return nil
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // Uniform 支持  →  对应 OpenGL 的 glUniform*
    // ═══════════════════════════════════════════════════════════════════
    //
    // Metal 中没有 uniform 关键字，而是通过 buffer 传递数据：
    //   OpenGL:  glUniform4f(location, r, g, b, a)
    //   Metal:   enc.setFragmentBytes(&color, length: 16, index: 1)
    //
    // 着色器端接收方式：
    //   constant float4 &uColor [[buffer(1)]]
    //
    // 使用示例：
    //   let color = SIMD4<Float>(1, 0, 0, 1)
    //   shader.setFragmentUniform(enc, index: 1, value: color)
    // ═══════════════════════════════════════════════════════════════════

    /// 设置顶点着色器 uniform（通过 buffer 传递，自动处理内存拷贝）
    /// - 相当于 glUniform* + 自动绑定到对应的 buffer 槽位
    func setVertexUniform<T>(
        _ encoder: MTLRenderCommandEncoder,
        index: Int,
        value: T
    ) {
        var v = value
        withUnsafeBytes(of: &v) { ptr in
            encoder.setVertexBytes(
                ptr.baseAddress!,
                length: ptr.count,
                index: index
            )
        }
    }

    /// 设置片段着色器 uniform（通过 buffer 传递）
    func setFragmentUniform<T>(
        _ encoder: MTLRenderCommandEncoder,
        index: Int,
        value: T
    ) {
        var v = value
        withUnsafeBytes(of: &v) { ptr in
            encoder.setFragmentBytes(
                ptr.baseAddress!,
                length: ptr.count,
                index: index
            )
        }
    }

    /// 设置 vertex + fragment 共享的 uniform（传递到两个阶段）
    func setUniform<T>(
        _ encoder: MTLRenderCommandEncoder,
        index: Int,
        value: T
    ) {
        setVertexUniform(encoder, index: index, value: value)
        setFragmentUniform(encoder, index: index, value: value)
    }
}
