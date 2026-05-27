import UIKit
import MetalKit
import simd

let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];  // gl_Position
    float3 color;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 color [[attribute(1)]];
};

vertex VertexOut vertex_main(
    VertexIn in [[stage_in]],
    constant float4x4 &m [[buffer(1)]]
) {
    VertexOut out;
    out.position = m * float4(in.position, 1.0);
    out.color = in.color;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    float4 outColor = float4(in.color, 1.0);
    return outColor;
}

"""

class Renderer: NSObject, MTKViewDelegate {
    private let shader_: MetalShader
    private let commandQueue_: MTLCommandQueue
    private let vertexBuffer_: MTLBuffer
    private let indexBuffer_: MTLBuffer
    private let pipelineState_: MTLRenderPipelineState
    private let indexCount_ = 6
    private var lastTime_: CFAbsoluteTime = 0  // 上一帧时间戳(帧率)
    private var lastRotTime_: CFAbsoluteTime = 0  // 上一帧时间戳(旋转)
    private var angle_: Float = 0              // 当前旋转角度（弧度）
    
    init(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        commandQueue_ = device.makeCommandQueue()!
        
        let vertices: [Float] = [
            // 位置           // 颜色
            -0.5, -0.5, 0.0, 1.0, 0.0, 0.0, // 左下
             0.5, -0.5, 0.0, 0.0, 1.0, 0.0, // 右下
            -0.5,  0.5, 0.0, 0.0, 0.0, 1.0, // 左上
             0.5,  0.5, 0.0, 1.0, 1.0, 0.0  // 右上
        ]
        vertexBuffer_ = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.size,
            options: []
        )!
        
        let indices: [UInt32] = [
            0, 1, 2,
            1, 3, 2
        ]
        indexBuffer_ = device.makeBuffer(
            bytes: indices,
            length: indices.count * MemoryLayout<UInt32>.size,
            options: []
        )!
        
        let s = MetalShader(device: device)
        shader_ = s
        guard shader_.UpdateLibrary(source: shaderSource)
            else {
            fatalError("着色器编译失败")
        }
        
        // 顶点描述符
        let vertexDescriptor = MTLVertexDescriptor()
        // attribute[0] position
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        // attribute[1] color
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 3
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        //layout
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 6
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        
        // pipeline state
        guard let p = shader_.MakeRenderPipeline(
            vertexFunc: "vertex_main",
            fragmentFunc: "fragment_main",
            vertexDescriptor: vertexDescriptor,
            colorPixelFormat: pixelFormat,
            depthPixelFormat: .invalid
        ) else {
            fatalError("管线状态创建失败")
        }
        pipelineState_ = p
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // 窗口大小变化时回调，暂不处理
    }
    
    func draw(in view: MTKView) {
        // ── 帧率统计 ──
        let now = CFAbsoluteTimeGetCurrent()
        if lastTime_ > 0 {
            let delta = now - lastTime_
            let fps = 1.0 / delta
            print(String(format: "delta: %.3fms  fps: %.1f", delta * 1000, fps))
        }
        lastTime_ = now

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
        
        // 用增量累加角度
        if lastRotTime_ > 0 {
            let delta = Float(now - lastRotTime_)
            angle_ += delta * 3.0  // 每秒 3 弧度
        }
        lastRotTime_ = now
        let cosA = cos(angle_), sinA = sin(angle_)

        // 宽高比修正：让正方形在屏幕上看起来也是正方形
        let drawableSize = view.drawableSize
        let aspect = Float(drawableSize.width / drawableSize.height)

        // Z轴旋转 + 宽高比修正（列主序）
        var matrix = simd_float4x4(
            columns: (
                SIMD4<Float>( cosA / aspect,  sinA, 0, 0),
                SIMD4<Float>(-sinA / aspect,  cosA, 0, 0),
                SIMD4<Float>(0,               0,    1, 0),
                SIMD4<Float>(0,               0,    0, 1)
            )
        )
        enc.setVertexBytes(&matrix, length: MemoryLayout<simd_float4x4>.size, index: 1)

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
        mtkView.enableSetNeedsDisplay = false  // 连续渲染模式
        mtkView.preferredFramesPerSecond = 60 // 锁定60帧
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
    
    // UISceneSession lifetime
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
