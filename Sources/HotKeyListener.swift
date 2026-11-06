import Carbon // 引入无需辅助功能权限的 Carbon 全局热键接口。
import Foundation // 引入日期用于快捷键去抖。

// MARK: - 全局 F11 热键监听

final class HotKeyListener { // 管理 Carbon 热键与事件处理器的生命周期。
    private var hotKeyReference: EventHotKeyRef? // 保存已注册热键引用。
    private var eventHandlerReference: EventHandlerRef? // 保存事件处理器引用。
    private let onPress: () -> Void // 保存 F11 触发时执行的操作。
    private var lastFireDate = Date.distantPast // 保存上次触发时间以过滤连发事件。

    init(onPress: @escaping () -> Void) { // 注入触发回调，避免与音频控制逻辑耦合。
        self.onPress = onPress // 保存外部回调。
    }

    func register() throws { // 注册无修饰键的 F11 全局热键。
        var eventType = EventTypeSpec( // 指定只监听热键按下事件。
            eventClass: OSType(kEventClassKeyboard), // 事件类别为键盘。
            eventKind: UInt32(kEventHotKeyPressed) // 事件类型为全局热键按下。
        )
        let userData = Unmanaged.passUnretained(self).toOpaque() // 将当前监听器传给 C 回调且不额外持有。
        let callback: EventHandlerUPP = { _, _, userData in // 创建 Carbon 事件回调。
            guard let userData = userData else { return noErr } // 忽略缺少上下文的异常事件。
            let listener = Unmanaged<HotKeyListener>.fromOpaque(userData).takeUnretainedValue() // 恢复 Swift 监听器实例。
            listener.fire() // 转发给实例进行去抖与回调。
            return noErr // 告知系统事件已经处理。
        }
        let handlerStatus = InstallEventHandler( // 在应用事件分发器上安装处理器。
            GetEventDispatcherTarget(), callback, 1, &eventType, userData, &eventHandlerReference // 注册一个热键事件类型。
        )
        guard handlerStatus == noErr else { throw HotKeyError.installationFailed(handlerStatus) } // 安装失败时报告状态码。
        let hotKeyID = EventHotKeyID(signature: 0x41463131, id: 1) // 使用 AF11 签名和编号 1 标识热键。
        let registerStatus = RegisterEventHotKey( // 注册全局 F11。
            UInt32(kVK_F11), 0, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyReference // 修饰键为 0，因此不要求 Command 等按键。
        )
        guard registerStatus == noErr else { // 检查热键是否被其他程序或系统保留。
            unregister() // 注册失败时清理已经安装的事件处理器。
            throw HotKeyError.registrationFailed(registerStatus) // 返回可诊断的注册错误。
        }
    }

    private func fire() { // 处理一次原始热键事件。
        let now = Date() // 获取本次事件时间。
        guard now.timeIntervalSince(lastFireDate) >= 0.35 else { return } // 350 毫秒内的重复事件直接忽略。
        lastFireDate = now // 记录有效触发时间。
        onPress() // 调用外部切换逻辑。
    }

    func unregister() { // 主动释放热键与事件处理器。
        if let hotKeyReference = hotKeyReference { // 仅在热键存在时注销。
            UnregisterEventHotKey(hotKeyReference) // 释放系统全局热键。
            self.hotKeyReference = nil // 防止重复注销。
        }
        if let eventHandlerReference = eventHandlerReference { // 仅在处理器存在时移除。
            RemoveEventHandler(eventHandlerReference) // 从事件分发器移除处理器。
            self.eventHandlerReference = nil // 防止重复移除。
        }
    }

    deinit { // 对象销毁时确保系统资源被释放。
        unregister() // 注销热键和处理器。
    }
}

enum HotKeyError: Error, CustomStringConvertible { // 定义热键安装与注册错误。
    case installationFailed(OSStatus) // 表示事件处理器安装失败。
    case registrationFailed(OSStatus) // 表示 F11 注册失败。

    var description: String { // 提供可操作的错误说明。
        switch self { // 根据失败阶段生成文本。
        case .installationFailed(let status): return "无法安装键盘事件处理器，系统状态码：\(status)" // 说明处理器安装错误。
        case .registrationFailed(let status): return "无法注册 F11，可能被其他程序占用，系统状态码：\(status)" // 说明热键冲突。
        }
    }
}
