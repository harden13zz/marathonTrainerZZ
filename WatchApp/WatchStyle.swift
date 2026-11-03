//
//  WatchStyle.swift
//  watchOS —— watchOS 专用小工具与可复用视图
//
//  单独成文件是为了保持 WatchContentView 可读。
//

import SwiftUI

enum NumberFormat {
    /// 心率：0 显示为 "--"
    static func heartRate(_ bpm: Double) -> String {
        bpm <= 0 ? "--" : String(format: "%.0f", bpm)
    }

    /// 距离：米转 km
    static func distance(_ meters: Double) -> String {
        meters >= 1000
            ? String(format: "%.2f km", meters / 1000)
            : String(format: "%.0f m", meters)
    }

    /// 卡路里
    static func calories(_ kcal: Double) -> String {
        String(format: "%.0f kcal", kcal)
    }
}

/// 手表上的「标签 + 数值」行，适合 glance 场景
struct WatchMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}
