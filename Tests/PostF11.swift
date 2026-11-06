import CoreGraphics // 引入底层键盘事件创建与投递接口。
import Foundation // 引入命令行输出所需的基础运行库。

// MARK: - F11 集成测试事件

let source = CGEventSource(stateID: .hidSystemState) // 使用硬件级事件源模拟真实功能键输入。
let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 103, keyDown: true) // 创建 F11 按下事件。
let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 103, keyDown: false) // 创建 F11 松开事件。
keyDown?.post(tap: .cgSessionEventTap) // 将按下事件投递到系统 HID 事件流。
keyUp?.post(tap: .cgSessionEventTap) // 将松开事件投递到系统 HID 事件流。
print("已投递一次 F11 按下与松开事件") // 输出测试事件已发送。
