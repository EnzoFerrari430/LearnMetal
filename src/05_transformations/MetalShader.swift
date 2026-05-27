import Metal
import MetalKit

final class MetalShader {
    // 属性
    let device_: MTLDevice // GPU device
    var library_: MTLLibrary? // 着色器库 可以从字符串更新
    
    init(device: MTLDevice) {
        self.device_ = device
        print("MetalShader 初始化成功")
    }
    
    // 从源码字符串重新编译着色器库（支持运行时热更新）
    // - 用法与 glShaderSource + glCompileShader 类似
    func UpdateLibrary(source: String) -> Bool {
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
    
    // 提取着色器方法 用于提取顶点着色器或者片段着色器
    func Function(name: String) -> MTLFunction? {
        guard let lib = library_ else {
            print("着色器库未初始化，请先调用 UpdateLibrary")
            return nil
        }
        
        guard let function = lib.makeFunction(name: name) else {
            print("着色器方法提取失败: \(name)")
            return nil
        }
        return function
    }
    
    // create render pipeline
    func MakeRenderPipeline(
        vertexFunc: String,
        fragmentFunc: String,
        vertexDescriptor: MTLVertexDescriptor,
        colorPixelFormat: MTLPixelFormat = .bgra8Unorm,
        depthPixelFormat: MTLPixelFormat = .depth32Float
    ) -> MTLRenderPipelineState? {
        
        guard let vert = Function(name: vertexFunc),
              let frag = Function(name: fragmentFunc) else {
            return nil
        }
        
        // 管线描述
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vert
        desc.fragmentFunction = frag
        desc.vertexDescriptor = vertexDescriptor
        
        desc.colorAttachments[0].pixelFormat = colorPixelFormat
        desc.depthAttachmentPixelFormat = depthPixelFormat
        
        // 创建管线
        do {
            return try device_.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("渲染管线创建失败: \(error.localizedDescription)")
            return nil
        }
        
    }
    
    // 计算管线
    func MakeComputePipeline(kernelFunc: String) -> MTLComputePipelineState? {
        guard let kernel = Function(name: kernelFunc) else { return nil }
        
        do {
            return try device_.makeComputePipelineState(function: kernel)
        } catch {
            print("计算管线创建失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 设置顶点着色器 uniform（通过 buffer 传递，自动处理内存拷贝）
    /// - 相当于 glUniform* + 自动绑定到对应的 buffer 槽位
    func SetVertexUniform<T>(
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
    func SetFragmentUniform<T>(
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
    func SetUniform<T>(
        _ encoder: MTLRenderCommandEncoder,
        index: Int,
        value: T
    ) {
        SetVertexUniform(encoder, index: index, value: value)
        SetFragmentUniform(encoder, index: index, value: value)
    }
    
}
