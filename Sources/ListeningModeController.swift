import CoreAudio // 引入 macOS 原生音频设备接口。
import Foundation // 引入基础数据类型与线程等待能力。

// MARK: - 聆听模式定义

enum ListeningMode: UInt32 { // 原始值与 macOS BTAudioHAL 的公开运行时行为保持一致。
    case off = 1 // 关闭全部聆听模式。
    case noiseCancellation = 2 // 主动降噪模式。
    case transparency = 3 // 通透模式。
    case adaptive = 4 // 自适应模式。

    var displayName: String { // 给状态输出提供稳定的中文名称。
        switch self { // 按枚举值返回对应名称。
        case .off: return "关闭" // 显示关闭模式。
        case .noiseCancellation: return "降噪" // 显示降噪模式。
        case .transparency: return "通透" // 显示通透模式。
        case .adaptive: return "自适应" // 显示自适应模式。
        }
    }
}

struct ListeningModeDevice { // 保存一个支持聆听模式切换的 Core Audio 设备快照。
    let id: AudioDeviceID // 保存 Core Audio 设备标识。
    let name: String // 保存便于识别的设备名称。
    let mode: ListeningMode // 保存读取时的当前聆听模式。
    let supportedModesMask: UInt32 // 保存设备支持的模式位掩码。
}

struct ToggleResult { // 保存一次切换的结果，供日志与测试输出使用。
    let deviceName: String // 保存被切换设备的名称。
    let from: ListeningMode // 保存切换前模式。
    let to: ListeningMode // 保存切换后模式。
}

enum ListeningModeError: Error, CustomStringConvertible { // 定义可向用户解释的失败原因。
    case audioHardwareUnavailable(OSStatus) // 表示音频设备枚举失败。
    case invalidPropertySize // 表示系统返回了非预期的数据长度。
    case propertyReadFailed(OSStatus) // 表示属性读取失败。
    case propertyWriteFailed(OSStatus) // 表示属性写入失败。
    case propertyNotSettable // 表示当前设备不允许写入聆听模式。
    case noCompatibleDevice // 表示没有已连接且支持切换的耳机。
    case unsupportedModePair // 表示设备未同时支持降噪和通透。

    var description: String { // 将内部错误转换为易读文本。
        switch self { // 按错误类型生成说明。
        case .audioHardwareUnavailable(let status): return "无法枚举音频设备，系统状态码：\(status)" // 说明枚举错误。
        case .invalidPropertySize: return "系统返回了异常的聆听模式数据长度" // 说明 ABI 数据异常。
        case .propertyReadFailed(let status): return "读取聆听模式失败，系统状态码：\(status)" // 说明读取错误。
        case .propertyWriteFailed(let status): return "写入聆听模式失败，系统状态码：\(status)" // 说明写入错误。
        case .propertyNotSettable: return "当前耳机的聆听模式属性不可写入" // 说明只读状态。
        case .noCompatibleDevice: return "未发现已连接的 AirPods 或其他兼容耳机" // 说明没有目标设备。
        case .unsupportedModePair: return "当前耳机不支持降噪与通透之间的切换" // 说明能力不满足需求。
        }
    }
}

// MARK: - Core Audio 控制器

final class ListeningModeController { // 封装设备发现、模式计算与写入。
    private let listeningModeSelector: AudioObjectPropertySelector = 0x6C73746D // lstm：当前聆听模式。
    private let supportedModesSelector: AudioObjectPropertySelector = 0x6C736D73 // lsms：支持的聆听模式位掩码。
    private let noiseCancellationBit: UInt32 = 0b001 // 位 0 表示支持降噪。
    private let transparencyBit: UInt32 = 0b010 // 位 1 表示支持通透。

    // MARK: 设备与属性读取

    private func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress { // 创建统一的属性地址。
        return AudioObjectPropertyAddress( // 使用全局作用域和主元素访问设备属性。
            mSelector: selector, // 指定要读取或写入的属性。
            mScope: kAudioObjectPropertyScopeGlobal, // 聆听模式属于设备全局属性。
            mElement: kAudioObjectPropertyElementMain // 使用 Core Audio 主元素。
        )
    }

    private func allAudioDeviceIDs() throws -> [AudioDeviceID] { // 枚举当前所有 Core Audio 设备。
        var address = propertyAddress(kAudioHardwarePropertyDevices) // 指定系统设备列表属性。
        var dataSize: UInt32 = 0 // 接收设备列表字节数。
        let sizeStatus = AudioObjectGetPropertyDataSize( // 先查询设备列表所需缓冲区大小。
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize // 查询系统对象而不是单个设备。
        )
        guard sizeStatus == noErr else { throw ListeningModeError.audioHardwareUnavailable(sizeStatus) } // 保留系统错误码。
        guard dataSize % UInt32(MemoryLayout<AudioDeviceID>.stride) == 0 else { throw ListeningModeError.invalidPropertySize } // 检查列表对齐。
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride // 计算设备数量。
        guard count > 0 else { return [] } // 没有音频设备时直接返回空列表。
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count) // 分配设备标识数组。
        let readStatus = deviceIDs.withUnsafeMutableBytes { buffer in // 将数组作为连续内存传给 Core Audio。
            AudioObjectGetPropertyData( // 读取完整设备列表。
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, buffer.baseAddress! // 写入数组缓冲区。
            )
        }
        guard readStatus == noErr else { throw ListeningModeError.audioHardwareUnavailable(readStatus) } // 检查读取结果。
        return deviceIDs // 返回原始设备标识列表。
    }

    private func readUInt32(_ selector: AudioObjectPropertySelector, deviceID: AudioDeviceID) throws -> UInt32 { // 读取四字节设备属性。
        var address = propertyAddress(selector) // 创建目标属性地址。
        var reportedSize: UInt32 = 0 // 接收系统声明的属性大小。
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &reportedSize) // 查询属性大小。
        guard sizeStatus == noErr else { throw ListeningModeError.propertyReadFailed(sizeStatus) } // 查询失败时保留状态码。
        guard reportedSize == UInt32(MemoryLayout<UInt32>.size) else { throw ListeningModeError.invalidPropertySize } // 防止错误 ABI 数据。
        var value: UInt32 = 0 // 保存读取到的属性值。
        var dataSize = reportedSize // 传入实际读取缓冲区大小。
        let readStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value) // 读取属性值。
        guard readStatus == noErr else { throw ListeningModeError.propertyReadFailed(readStatus) } // 读取失败时保留状态码。
        guard dataSize == UInt32(MemoryLayout<UInt32>.size) else { throw ListeningModeError.invalidPropertySize } // 检查实际返回长度。
        return value // 返回原始 UInt32 值。
    }

    private func deviceName(_ deviceID: AudioDeviceID) -> String { // 读取设备名称，失败时使用占位名称。
        var address = propertyAddress(kAudioObjectPropertyName) // 指定设备名称属性。
        let valuePointer = UnsafeMutablePointer<CFString>.allocate(capacity: 1) // 分配明确的 CFString 存储地址。
        valuePointer.initialize(to: "未知音频设备" as CFString) // 初始化名称存储容器。
        defer { // 确保所有返回路径都释放临时存储。
            valuePointer.deinitialize(count: 1) // 销毁容器中的 Core Foundation 引用。
            valuePointer.deallocate() // 释放临时名称存储内存。
        }
        var dataSize = UInt32(MemoryLayout<CFString>.size) // 设置名称属性数据长度。
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, valuePointer) // 读取设备名称。
        return status == noErr ? valuePointer.pointee as String : "未知音频设备" // 将 CFString 桥接为 Swift 字符串。
    }

    private func defaultOutputDeviceID() -> AudioDeviceID? { // 获取当前默认输出设备，用于优先选择目标。
        var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice) // 指定默认输出设备属性。
        var deviceID = AudioDeviceID(kAudioObjectUnknown) // 初始化设备标识。
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size) // 设置设备标识数据长度。
        let status = AudioObjectGetPropertyData( // 从系统对象读取默认输出设备。
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID // 写入设备标识。
        )
        guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else { return nil } // 无效结果按无默认设备处理。
        return deviceID // 返回默认输出设备标识。
    }

    // MARK: 目标设备选择

    func compatibleDevices() throws -> [ListeningModeDevice] { // 找出所有暴露聆听模式属性的设备。
        var result: [ListeningModeDevice] = [] // 初始化兼容设备列表。
        for deviceID in try allAudioDeviceIDs() { // 逐个检查系统中的音频设备。
            var address = propertyAddress(listeningModeSelector) // 创建聆听模式属性地址。
            guard AudioObjectHasProperty(deviceID, &address) else { continue } // 普通扬声器没有该属性，直接跳过。
            guard let rawMode = try? readUInt32(listeningModeSelector, deviceID: deviceID) else { continue } // 无法读取的控制端点不参与切换。
            guard let mode = ListeningMode(rawValue: rawMode) else { continue } // 忽略未知或尚未解析的模式值。
            let supportMask = (try? readUInt32(supportedModesSelector, deviceID: deviceID)) ?? 0 // 读取支持位掩码。
            result.append(ListeningModeDevice( // 保存当前兼容设备快照。
                id: deviceID, // 保存设备标识。
                name: deviceName(deviceID), // 保存设备名称。
                mode: mode, // 保存当前模式。
                supportedModesMask: supportMask // 保存支持位掩码。
            ))
        }
        return result // 返回所有兼容设备。
    }

    private func targetDevice() throws -> ListeningModeDevice { // 按输出路由与名称选择唯一操作目标。
        let devices = try compatibleDevices() // 获取当前兼容设备。
        guard !devices.isEmpty else { throw ListeningModeError.noCompatibleDevice } // 没有设备时给出明确错误。
        if let defaultID = defaultOutputDeviceID(), let selected = devices.first(where: { $0.id == defaultID }) { // 优先使用默认输出控制端点。
            return selected // 默认输出设备就是当前用户正在使用的耳机。
        }
        if let airPods = devices.first(where: { $0.name.localizedCaseInsensitiveContains("AirPods") }) { // 其次匹配 AirPods 名称。
            return airPods // 处理控制端点与默认输出端点不同的情况。
        }
        return devices[0] // 只有一个或其他兼容设备时使用首个候选。
    }

    // MARK: 模式计算与写入

    static func nextMode(current: ListeningMode, supportMask: UInt32) -> ListeningMode? { // 计算降噪与通透之间的下一状态。
        let supportsANC = supportMask & 0b001 != 0 // 检查是否支持主动降噪。
        let supportsTransparency = supportMask & 0b010 != 0 // 检查是否支持通透模式。
        switch current { // 根据当前模式决定目标模式。
        case .noiseCancellation: // 当前为降噪时优先切到通透。
            return supportsTransparency ? .transparency : nil // 不支持通透时拒绝无效切换。
        case .transparency: // 当前为通透时优先切到降噪。
            return supportsANC ? .noiseCancellation : nil // 不支持降噪时拒绝无效切换。
        case .off, .adaptive: // 当前为关闭或自适应时进入可稳定往返的状态。
            if supportsANC { return .noiseCancellation } // 优先进入降噪模式。
            return supportsTransparency ? .transparency : nil // 没有降噪能力时尝试通透。
        }
    }

    private func writeMode(_ mode: ListeningMode, deviceID: AudioDeviceID) throws { // 将目标模式写入 Core Audio。
        var address = propertyAddress(listeningModeSelector) // 创建当前模式属性地址。
        var settable = DarwinBoolean(false) // 接收属性是否可写的标记。
        let settableStatus = AudioObjectIsPropertySettable(deviceID, &address, &settable) // 查询写入能力。
        guard settableStatus == noErr else { throw ListeningModeError.propertyWriteFailed(settableStatus) } // 查询失败时保留状态码。
        guard settable.boolValue else { throw ListeningModeError.propertyNotSettable } // 明确拒绝只读属性。
        var rawValue = mode.rawValue // 将枚举转换为目标 UInt32。
        let dataSize = UInt32(MemoryLayout<UInt32>.size) // 聆听模式始终写入四字节。
        let writeStatus = AudioObjectSetPropertyData(deviceID, &address, 0, nil, dataSize, &rawValue) // 请求系统切换模式。
        guard writeStatus == noErr else { throw ListeningModeError.propertyWriteFailed(writeStatus) } // 写入失败时保留状态码。
    }

    func toggle() throws -> ToggleResult { // 执行一次读取、切换并立即返回的流程。
        let device = try targetDevice() // 每次触发都重新发现设备，支持耳机热插拔。
        guard let next = Self.nextMode(current: device.mode, supportMask: device.supportedModesMask) else { // 计算有效目标模式。
            throw ListeningModeError.unsupportedModePair // 能力不满足时停止，不写入未知值。
        }
        try writeMode(next, deviceID: device.id) // 请求系统写入目标模式，不在写入后等待或轮询。
        return ToggleResult(deviceName: device.name, from: device.mode, to: next) // 系统接受写入后立即返回目标状态。
    }
}
