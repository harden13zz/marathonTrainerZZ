//
//  HealthKitService.swift
//  iOS —— HealthKit 授权占位（Step 0）
//
//  现在只申请「读」权限，用来验证：
//  - entitlements 里的 com.apple.developer.healthkit 被免费证书正确签名；
//  - Info.plist 的 NSHealthShareUsageDescription 齐全；
//  - 弹窗能正常出现（任务 2 才真正读取 HRV / 静息心率 / 睡眠）。
//
//  注意：免费签名下 HealthKit capability 是否能被 Apple Development 证书
//  接受，是本文件要重点验证的内容之一。如果这里报 "Missing entitlement"，
//  第 0 步就要立刻把这个问题反馈出来，不要往下写 Step 2。
//

import Foundation
import HealthKit

@MainActor
final class HealthKitService {

    static let shared = HealthKitService()

    private let store = HKHealthStore()

    /// Step 0 先要这几项；任务 2 再补睡眠、步频、运动记录
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { types.insert(hr) }
        if let rhr = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { types.insert(rhr) }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(hrv) }
        if let dist = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) { types.insert(dist) }
        types.insert(HKObjectType.workoutType())
        return types
    }

    /// 返回一段人类可读的状态文本，直接展示在 UI 上
    func requestAuthorization() async -> String {
        guard HKHealthStore.isHealthDataAvailable() else {
            return "本机无 HealthKit（模拟器 / iPad）"
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            // 注意：出于隐私，HealthKit 不会告诉你用户「拒绝」了哪一项，
            // 只能告诉你「弹窗流程走完了」。真实是否有数据要等 Task 2 的查询。
            return "弹窗流程已完成"
        } catch {
            return "失败：\(error.localizedDescription)"
        }
    }
}
