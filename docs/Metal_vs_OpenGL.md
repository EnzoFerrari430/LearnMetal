# Metal vs OpenGL 类比参考

> 以 `02_hello_triangle` 为例，说明 Metal 三个核心类的职责，
> 并与 Windows 下 OpenGL 开发流程做对比。

---

## 三个类的职责对比

### 1. AppDelegate — 应用入口

| Metal | 类比 Win32 OpenGL |
|---|---|
| `@main` 标记，iOS 应用启动点 | `WinMain()` 函数 |
| 注册 UISceneConfiguration | `WNDCLASS` 注册窗口类 |
| 不直接参与 UI 和渲染 | 不直接处理 OpenGL 上下文 |

```swift
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration",
                                    sessionRole: session.role)
    }
}
```

### 2. SceneDelegate — 窗口 / 场景初始化

| Metal | 类比 Win32 OpenGL |
|---|---|
| 创建 `UIWindow` | `CreateWindow()` 创建窗口 |
| 创建 `MTLDevice` | `ChoosePixelFormat()` + `SetPixelFormat()` 选择像素格式 |
| 创建 `MTKView` 并配置 `clearColor` | `glClearColor()` 设置清屏色 |
| 创建 Renderer 并绑定为 delegate | 初始化场景数据 + 绑定渲染循环 |

```swift
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: ...) {
        let device = MTLCreateSystemDefaultDevice()!          // 获取 GPU
        let mtkView = MTKView(frame: window.bounds, device: device) // 创建渲染视图
        mtkView.clearColor = MTLClearColor(...)               // 类似 glClearColor
        renderer = Renderer(device: device)
        mtkView.delegate = renderer                           // 绑定渲染回调
    }
}
```

### 3. Renderer — 渲染循环

| Metal 步骤 | 对应 OpenGL 步骤 |
|---|---|
| `currentRenderPassDescriptor` | 获取 framebuffer / renderbuffer |
| `makeCommandBuffer()` | 准备命令缓冲区（OpenGL 隐式） |
| `makeRenderCommandEncoder()` | `glBegin(...)` / 设置状态 |
| `enc.endEncoding()` | `glEnd()` / 结束绘制 |
| `buf.present(view.currentDrawable!)` | `SwapBuffers(hdc)` 交换双缓冲 |
| `buf.commit()` | 提交命令到 GPU 执行队列 |

```swift
func draw(in view: MTKView) {
    guard let desc = view.currentRenderPassDescriptor,
          let buf = commandQueue.makeCommandBuffer(),
          let enc = buf.makeRenderCommandEncoder(descriptor: desc)
    else { return }

    // 录制绘制指令...
    enc.endEncoding()

    buf.present(view.currentDrawable!)    // 类似 SwapBuffers
    buf.commit()                          // 提交给 GPU
}
```

---

## 完整调用链

```
Metal                              OpenGL on Windows
─────                              ─────────────────
AppDelegate                        WinMain()
  ↓                                  ↓
SceneDelegate                      CreateWindow()
  → MTKView + MTLDevice              → HDC + HGLRC + SetPixelFormat
  → Renderer                           → 场景初始化
    ↓                                  ↓
MTKView 驱动 draw(in:)              WM_PAINT 消息循环
  → RenderPassDescriptor               → glBindFramebuffer
  → CommandBuffer                      → 隐式命令缓冲
  → RenderCommandEncoder               → glBegin / 绘制调用
  → endEncoding                        → glEnd
  → present + commit                 → SwapBuffers
```

---

## 快速记忆

| 类 | 一句话 | 对应 |
|---|---|---|
| `AppDelegate` | 应用启动入口 | `WinMain` |
| `SceneDelegate` | 创建窗口、设置 GPU、组装 UI | `CreateWindow` + 像素格式 |
| `Renderer` | 每帧渲染逻辑 | `WM_PAINT` + `SwapBuffers` |
