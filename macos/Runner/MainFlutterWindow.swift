import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // 初始窗口大小:宽度略大于高度(横屏比例)
    self.setContentSize(NSSize(width: 1000, height: 700))

    // 最小窗口大小:防止窗口缩得太小导致界面错乱
    self.contentMinSize = NSSize(width: 860, height: 600)

    // 首次启动居中显示
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 桌面歌词浮窗:为每个新建子窗口注册插件(子窗口有独立引擎),
    // 并把子窗口设为透明(毛玻璃圆角需要窗口非不透明,否则显示黑底)。
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      DispatchQueue.main.async {
        guard let window = controller.view.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
      }
    }

    super.awakeFromNib()
  }
}
