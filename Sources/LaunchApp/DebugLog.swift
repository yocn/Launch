import Foundation

// 排查问题用的调试日志：debug 构建，或打包时设置 LAUNCH_DEBUG_LOG=1 才编译进去，正常发布包不含
enum DebugLog {
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG || LAUNCH_DEBUG_LOG
        AppLog.shared.info("[调试] \(message())")
        #endif
    }
}
