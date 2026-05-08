import UIKit
import MetalKit

// MARK: - Renderer

class Renderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue

    init(device: MTLDevice) {
        commandQueue = device.makeCommandQueue()!
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // 窗口大小变化时回调，暂不处理
    }

    func draw(in view: MTKView) {
        guard
            let desc = view.currentRenderPassDescriptor,
            let buf = commandQueue.makeCommandBuffer(),
            let enc = buf.makeRenderCommandEncoder(descriptor: desc)
        else { return }

        enc.endEncoding()
        buf.present(view.currentDrawable!)
        buf.commit()
    }
}

// MARK: - Scene Delegate

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var renderer: Renderer?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        print("GPU: \(device.name)")

        let window = UIWindow(windowScene: windowScene)

        let mtkView = MTKView(frame: window.bounds, device: device)
        renderer = Renderer(device: device)
        mtkView.delegate = renderer
        mtkView.clearColor = MTLClearColor(red: 0.2, green: 0.3, blue: 0.3, alpha: 1.0)

        let vc = UIViewController()
        vc.view = mtkView
        window.rootViewController = vc
        window.makeKeyAndVisible()
        self.window = window
    }
}

// MARK: - App Delegate

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
