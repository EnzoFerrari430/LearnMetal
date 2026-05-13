import UIKit
import MetalKit

let shaderSource = """
#include <metal_stdlib>
using namespace metal;

// 从顶点着色器传到片段着色器的结构体 → 相当于 OpenGL 的 out / in varying
struct RasterizerData {
    float4 position [[position]];   // 相当于 gl_Position
    float4 vertexColor;             // 相当于 out vec4 vertexColor / in vec4 vertexColor
};

vertex RasterizerData vertex_main(
    constant packed_float3 *vertices [[buffer(0)]],  // 相当于 layout(location=0) in vec3 aPos
    uint vid [[vertex_id]]                            // 内置顶点索引
) {
    RasterizerData out;
    out.position = float4(vertices[vid], 1.0);       // 相当于 gl_Position = vec4(aPos, 1.0)
    out.vertexColor = float4(0.5, 0.0, 0.0, 1.0);    // 相当于 vertexColor = vec4(0.5, 0.0, 0.0, 1.0)
    return out;
}

fragment float4 fragment_main(
    RasterizerData in [[stage_in]]                    // 相当于 in vec4 vertexColor
) {
    return in.vertexColor;                            // 相当于 FragColor = vertexColor
}
"""

//
class Renderer: NSObject, MTKViewDelegate {
    private let shader_: MetalShader
    private let commandQueue_: MTLCommandQueue
    private let vertexBuffer_: MTLBuffer
    private let pipelineState_: MTLRenderPipelineState
    private let vertexCount_ = 3

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        commandQueue_ = device.makeCommandQueue()!

        let vertices: [Float] = [
            -0.8, -0.4, 0.0,   // 左下
             0.8, -0.4, 0.0,   // 右下
             0.0,  0.4, 0.0    // 顶部
        ]
        vertexBuffer_ = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.size,
            options: []
        )!

        // ── 用 MetalShader 管理着色器 ──
        let s = MetalShader(device: device)
        shader_ = s
        guard shader_.updateLibrary(source: shaderSource) else {
            fatalError("着色器编译失败")
        }

        // 顶点描述符（描述顶点缓冲区的数据排布）
        let vertexDesc = MTLVertexDescriptor()
        vertexDesc.attributes[0].format = .float3          // 3 个 float → 位置
        vertexDesc.attributes[0].offset = 0
        vertexDesc.attributes[0].bufferIndex = 0
        vertexDesc.layouts[0].stride = MemoryLayout<Float>.size * 3
        vertexDesc.layouts[0].stepFunction = .perVertex

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

        // ── 绑定顶点缓冲到 buffer(0) ≈ glBindBuffer + glVertexAttribPointer ──
        enc.setVertexBuffer(vertexBuffer_, offset: 0, index: 0)

        // ── 绘制三角形 ≈ glDrawArrays(GL_TRIANGLES, 0, 3) ──
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount_)

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


// App Delegate
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
