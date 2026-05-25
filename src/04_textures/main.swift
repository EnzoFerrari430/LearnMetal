import UIKit
import MetalKit

let shaderSourcewith2attribute = """
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]]; // gl_Position
    float3 color;
    float2 texCoord;              // 纹理坐标传给片段着色器
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 color [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 1.0);
    out.color = in.color;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 fragment_main(
    VertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    sampler smp [[sampler(0)]]
) {
    float4 texColor = tex.sample(smp, in.texCoord);
    return mix(texColor, float4(in.color, 1.0), 0.3);  // 70%纹理 + 30%颜色
}
"""

class Renderer: NSObject, MTKViewDelegate {
    private let shader_: MetalShader
    private let commandQueue_: MTLCommandQueue
    private let vertexBuffer_: MTLBuffer
    private let indexBuffer_: MTLBuffer
    private let pipelineState_: MTLRenderPipelineState
    private let texture_: MTLTexture
    private let sampler_: MTLSamplerState
    private let indexCount_ = 6
    
    init(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        commandQueue_ = device.makeCommandQueue()!

        let vertices: [Float] = [
            // 位置           // 颜色        // 纹理坐标
            -0.8, -0.4, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0,  // 左下
             0.8, -0.4, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0,  // 右下
            -0.8,  0.4, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0,  // 左上
             0.8,  0.4, 0.0, 1.0, 1.0, 0.0, 1.0, 0.0   // 右上
        ]
        vertexBuffer_ = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.size,
            options: []
        )!

        // 索引 buffer → 相当于 OpenGL 的 glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, indices)
        // 两个三角形：左下-右下-左上  和  右下-右上-左上
        let indices: [UInt32] = [
            0, 1, 2,  // 第一个三角形
            1, 3, 2   // 第二个三角形
        ]
        indexBuffer_ = device.makeBuffer(
            bytes: indices,
            length: indices.count * MemoryLayout<UInt32>.size,
            options: []
        )!

        // ── 用 MetalShader 管理着色器 ──
        let s = MetalShader(device: device)
        shader_ = s
        guard shader_.updateLibrary(source: shaderSourcewith2attribute) else {
            fatalError("着色器编译失败")
        }

        // 顶点描述符
        let vertexDesc = MTLVertexDescriptor()
        // attribute[0]: 位置 float3
        vertexDesc.attributes[0].format = .float3
        vertexDesc.attributes[0].offset = 0
        vertexDesc.attributes[0].bufferIndex = 0
        // attribute[1]: 颜色 float3
        vertexDesc.attributes[1].format = .float3
        vertexDesc.attributes[1].offset = MemoryLayout<Float>.size * 3
        vertexDesc.attributes[1].bufferIndex = 0
        // attribute[2]: 纹理坐标 float2
        vertexDesc.attributes[2].format = .float2
        vertexDesc.attributes[2].offset = MemoryLayout<Float>.size * 6
        vertexDesc.attributes[2].bufferIndex = 0
        // layout: stride = 8 个 float = 32 字节
        vertexDesc.layouts[0].stride = MemoryLayout<Float>.size * 8
        vertexDesc.layouts[0].stepFunction = .perVertex

        // ── 加载纹理 container.jpg ──
        let loader = MTKTextureLoader(device: device)
        guard let texURL = Bundle.main.url(
            forResource: "container",
            withExtension: "jpg",
            subdirectory: "textures"
        ) else {
            fatalError("找不到 container.jpg")
        }
        texture_ = try! loader.newTexture(URL: texURL, options: [
            .origin: MTKTextureLoader.Origin.flippedVertically  // Metal y 轴向上，UIKit 向下
        ])

        // ── 采样器 ──
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        sampler_ = device.makeSamplerState(descriptor: samplerDesc)!

        // ── 用 MetalShader 创建管线 ──
        guard let p = shader_.makeRenderPipeline(
            vertexFunc: "vertex_main",
            fragmentFunc: "fragment_main",
            vertexDescriptor: vertexDesc,
            colorPixelFormat: pixelFormat,
            depthPixelFormat: .invalid   // 本例不需要深度测试
        ) else {
            fatalError("渲染管线创建失败")
        }
        pipelineState_ = p
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // 窗口大小变化时回调，暂不处理
    }

    func draw(in view: MTKView) {
        // ─────────────────────────────────────────────────────────────────────
        // guard-let 的作用：依次尝试获取三个关键对象，任何一个获取失败就提前退出
        // ─────────────────────────────────────────────────────────────────────
        guard
            // 1. 获取当前帧的渲染目标描述（color attachment 等配置）
            //    如果 MTKView 当前没有可用的 drawable，返回 nil
            let desc = view.currentRenderPassDescriptor,

            // 2. 从命令队列中创建一个命令缓冲区，用于存放本次渲染的所有 GPU 指令
            let buf = commandQueue_.makeCommandBuffer(),

            // 3. 基于上面的渲染描述创建编码器，开始"记录"顶点/片段着色器调用等绘制指令
            let enc = buf.makeRenderCommandEncoder(descriptor: desc)
        else { return }
        // 上面任意一步失败（nil），说明当前帧还没准备好，直接 return，等下一帧重试

        // ── 设置管线状态 ──
        enc.setRenderPipelineState(pipelineState_)

        // ── 绑定顶点缓冲 ──
        enc.setVertexBuffer(vertexBuffer_, offset: 0, index: 0)

        // ── 绑定纹理和采样器 ≈ glBindTexture + glTexParameteri ──
        enc.setFragmentTexture(texture_, index: 0)
        enc.setFragmentSamplerState(sampler_, index: 0)

        // ── 绘制（索引绘制）≈ glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0) ──
        enc.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount_,
            indexType: .uint32,
            indexBuffer: indexBuffer_,
            indexBufferOffset: 0
        )

        // ── 结束编码：告诉编码器指令记录完毕 ──
        enc.endEncoding()

        // ── 提交命令缓冲区：将编码好的 GPU 指令发送给 GPU 执行 ──
        // 同时告诉 Metal：等渲染完成后，把结果展示到屏幕上（present）
        buf.present(view.currentDrawable!)

        // ── 正式提交：命令缓冲区进入 GPU 执行队列 ──
        buf.commit()
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var renderer: Renderer?

    func scene(_ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        print("GPU: \(device.name)")

        let window = UIWindow(windowScene: windowScene)

        let mtkView = MTKView(frame: window.bounds, device: device)
        renderer = Renderer(device: device, pixelFormat: mtkView.colorPixelFormat)
        mtkView.delegate = renderer
        mtkView.clearColor = MTLClearColor(red: 0.2, green: 0.3, blue: 0.3, alpha: 1.0)
        
        let vc = UIViewController()
        vc.view = mtkView
        window.rootViewController = vc
        window.makeKeyAndVisible()
        self.window = window
        
    }
}


@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
        [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return true
    }
    
    // UISceneSession 生命周期
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration",
                                    sessionRole: connectingSceneSession.role)
    }
}
