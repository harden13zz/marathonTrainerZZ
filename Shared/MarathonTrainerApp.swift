//
//  MarathonTrainerApp.swift
//  Shared —— iOS App 与 watchOS App 共用同一个 @main 入口
//
//  ⚠️ 这是 Step 0（骨架验证）阶段的刻意设计：
//  不等待 iOS 下发课表，手表 App 必须能独立启动。免费签名下 Watch App
//  的安装链路本身是最大风险点，先保证「手表上能打开并记录一次运动」。
//
//  进入 Task 5/6/7 后，iOS 侧会改为 TabView（首页 / 历史 / 设置），
//  Watch 侧会改为基于课表状态机的训练执行页。届时两者拆成各自的 @main 文件。
//

import SwiftUI

@main
struct MarathonTrainerApp: App {

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// 按平台选择根视图。用 `#if` 而不是两个 App 类型，避免共享文件在
/// 两个 target 里出现重复的 @main 符号。
struct RootView: View {
    var body: some View {
        #if os(watchOS)
        WatchContentView()
        #else
        ContentView()
        #endif
    }
}
