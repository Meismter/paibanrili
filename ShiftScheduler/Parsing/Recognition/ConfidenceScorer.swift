import Foundation

/// 置信度打分器（R06，共享约定 #7）。
///
/// 规则（任务要求：日期+时间+班次全中 ≥0.9，缺一项降级，<0.6 需人工确认）：
/// - 权重分配：日期 0.35 + 班次 0.35 + 时间段 0.15 + 成员 0.15 → 全中 = 1.0；
/// - 缺时间/成员各降 0.15、缺班次降 0.35；
/// - <0.6 的条目 UI 黄色高亮强制人工过目；≥0.8 允许直接确认。
enum ConfidenceScorer {

    /// 自动确认阈值（≥ 此值绿勾直接确认）
    static let autoConfirmThreshold = 0.8

    /// 人工确认阈值（< 此值黄色高亮强制过目）
    static let manualReviewThreshold = 0.6

    // MARK: - 打分

    /// 按要素命中情况计算置信度
    static func score(hasDate: Bool,
                      hasTimeRange: Bool,
                      hasShiftMatch: Bool,
                      hasName: Bool) -> Double {
        var score = 0.0
        if hasDate { score += 0.35 }
        if hasShiftMatch { score += 0.35 }
        if hasTimeRange { score += 0.15 }
        if hasName { score += 0.15 }
        return min(max(score, 0), 1)
    }

    /// 是否需要人工确认
    static func needsManualReview(_ confidence: Double) -> Bool {
        confidence < manualReviewThreshold
    }

    /// 是否可自动确认
    static func canAutoConfirm(_ confidence: Double) -> Bool {
        confidence >= autoConfirmThreshold
    }

    /// 人工修正后统一抬升至"已确认"档
    static let manuallyConfirmedScore = 0.95
}
