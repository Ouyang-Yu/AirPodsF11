import Carbon // 引入 Carbon 后台应用事件循环，避免加载完整界面框架。
import Foundation // 引入命令行参数、日志与运行循环。

// MARK: - Carbon 事件循环链接

@_silgen_name("RunApplicationEventLoop") // 链接 macOS 自 10.0 起提供的 Carbon C 函数。
private func runCarbonApplicationEventLoop() -> Void // 声明 Swift 侧调用签名，不引入额外界面框架。

// MARK: - 通用输出

func writeLog(_ message: String) { // 将运行信息写到标准错误，便于 launchd 或终端收集。
    let timestamp = ISO8601DateFormatter().string(from: Date()) // 生成标准化日志时间。
    FileHandle.standardError.write(Data("[\(timestamp)] \(message)\n".utf8)) // 输出单行日志。
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) { // 提供轻量自检断言，不引入测试框架。
    guard condition() else { // 检查断言是否成立。
        writeLog("自检失败：\(message)") // 输出具体失败项目。
        exit(1) // 自检失败时返回非零状态码。
    }
}

// MARK: - 命令行自检与诊断

let controller = ListeningModeController() // 创建共享的聆听模式控制器。
let arguments = Set(CommandLine.arguments.dropFirst()) // 将参数转换为集合以便快速判断。

if arguments.contains("--self-test") { // 执行不访问真实耳机的模式计算测试。
    require(ListeningModeController.nextMode(current: .noiseCancellation, supportMask: 0b011) == .transparency, "降噪应切换到通透") // 验证降噪到通透。
    require(ListeningModeController.nextMode(current: .transparency, supportMask: 0b011) == .noiseCancellation, "通透应切换到降噪") // 验证通透到降噪。
    require(ListeningModeController.nextMode(current: .adaptive, supportMask: 0b111) == .noiseCancellation, "自适应应进入降噪") // 验证自适应分支。
    require(ListeningModeController.nextMode(current: .off, supportMask: 0b011) == .noiseCancellation, "关闭模式应进入降噪") // 验证关闭分支。
    require(ListeningModeController.nextMode(current: .noiseCancellation, supportMask: 0b001) == nil, "缺少通透能力时不应写入") // 验证能力检查。
    require(ListeningModeController.nextMode(current: .transparency, supportMask: 0b010) == nil, "缺少降噪能力时不应写入") // 验证反向能力检查。
    writeLog("全部 6 项模式计算自检通过") // 报告自检结果。
    exit(0) // 自检完成后正常退出。
}

if arguments.contains("--check-hotkey") { // 单独验证 F11 能否在当前系统注册。
    let listener = HotKeyListener(onPress: {}) // 创建不会执行切换的测试监听器。
    do { // 捕获热键注册错误。
        try listener.register() // 尝试注册 F11。
        writeLog("F11 全局热键注册成功") // 报告注册成功。
        listener.unregister() // 立即释放测试热键。
        exit(0) // 测试完成后正常退出。
    } catch { // 处理热键安装或占用错误。
        writeLog("\(error)") // 输出具体错误。
        exit(1) // 返回失败状态码。
    }
}

if arguments.contains("--status") { // 输出当前兼容设备及模式，不修改任何状态。
    do { // 捕获设备枚举错误。
        let devices = try controller.compatibleDevices() // 读取当前兼容设备。
        if devices.isEmpty { // 处理未发现兼容耳机的情况。
            writeLog("未发现支持聆听模式控制的已连接耳机") // 提示先连接 AirPods。
        } else { // 输出每一个兼容设备。
            for device in devices { // 遍历兼容设备快照。
                writeLog("\(device.name)：\(device.mode.displayName)，支持位掩码 \(device.supportedModesMask)，设备 ID \(device.id)") // 输出诊断信息。
            }
        }
        exit(0) // 状态查询完成后正常退出。
    } catch { // 处理 Core Audio 枚举错误。
        writeLog("\(error)") // 输出具体错误。
        exit(1) // 返回失败状态码。
    }
}

if arguments.contains("--toggle") { // 提供一次性切换命令，便于不经过热键验证硬件。
    do { // 捕获设备读取与切换写入错误。
        let result = try controller.toggle() // 执行一次真实切换。
        writeLog("\(result.deviceName)：\(result.from.displayName) → \(result.to.displayName)") // 输出已提交的切换结果。
        exit(0) // 切换完成后正常退出。
    } catch { // 处理无设备或系统写入错误。
        writeLog("\(error)") // 输出具体错误。
        exit(1) // 返回失败状态码。
    }
}

// MARK: - 后台热键服务

let workerQueue = DispatchQueue(label: "local.airpodsf11.worker") // 使用串行队列避免连续触发造成并发写入。
let listener = HotKeyListener { // 创建 F11 监听器并注入切换回调。
    workerQueue.async { // 将音频操作移出键盘事件回调，避免阻塞系统事件处理。
        do { // 捕获每次切换的错误，保证后台服务继续运行。
            let result = try controller.toggle() // 执行降噪与通透切换。
            writeLog("\(result.deviceName)：\(result.from.displayName) → \(result.to.displayName)") // 记录已提交结果。
        } catch { // 处理耳机未连接或属性不可用等情况。
            writeLog("切换失败：\(error)") // 记录错误并等待下一次 F11。
        }
    }
}

do { // 捕获启动时的热键注册错误。
    try listener.register() // 注册全局 F11 热键。
    writeLog("AirPodsF11 已启动；按 F11 切换降噪与通透") // 报告服务就绪。
    runCarbonApplicationEventLoop() // 进入 Carbon 原生事件循环，仅在有事件时唤醒。
} catch { // 热键不可用时退出而不是假装运行。
    writeLog("启动失败：\(error)") // 输出启动失败原因。
    exit(1) // 返回失败状态码。
}
