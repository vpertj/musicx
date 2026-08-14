import Cocoa
import FlutterMacOS

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

    super.awakeFromNib()
  }
}
