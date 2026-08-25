import Foundation

// MARK: - 草稿条目
//
// 注：EventKitService.swift 中原有的最小版 DraftEntry 定义已随 T03 落地删除，
// 本文件是唯一权威定义（共享约定 #6：解析结果为值类型，与数据库解耦）。

/// 解析草稿条目：识别/导入结果的可修正值类型（架构 §3）
struct DraftEntry: Identifiable, Sendable {
    var id = UUID()
    /// 归属日期（自然日 12:00 本地）
    var attributedDate: Date
    /// 成员名原文；未匹配到 Member 时保留原文
    var memberName: String
    var matchedMemberID: UUID?
    /// 识别出的班次原文（如 "早"、"夜班"），人工修正后更新为规范班次名
    var shiftLabel: String
    var matchedShiftID: UUID?
    /// 置信度 0~1：<0.6 UI 黄色高亮强制过目（共享约定 #7）
    var confidence: Double
    /// 原始行，供人工修正参照
    var rawLine: String

    init(id: UUID = UUID(),
         attributedDate: Date,
         memberName: String,
         matchedMemberID: UUID? = nil,
         shiftLabel: String,
         matchedShiftID: UUID? = nil,
         confidence: Double,
         rawLine: String) {
        self.id = id
        self.attributedDate = DateUtils.noon(of: attributedDate)
        self.memberName = memberName
        self.matchedMemberID = matchedMemberID
        self.shiftLabel = shiftLabel
        self.matchedShiftID = matchedShiftID
        self.confidence = confidence
        self.rawLine = rawLine
    }

    /// 置信度档位（供预览页配色）
    var confidenceLevel: ConfidenceLevel {
        ConfidenceLevel(confidence: confidence)
    }
}

/// 置信度三档（共享约定 #7：≥0.8 直接确认 / 0.6~0.8 正常展示 / <0.6 黄色高亮）
enum ConfidenceLevel: Sendable {
    case autoConfirm   // ≥0.8 绿勾
    case normal        // 0.6~0.8 正常
    case manualReview  // <0.6 黄色高亮

    init(confidence: Double) {
        if confidence >= ConfidenceScorer.autoConfirmThreshold {
            self = .autoConfirm
        } else if confidence >= ConfidenceScorer.manualReviewThreshold {
            self = .normal
        } else {
            self = .manualReview
        }
    }
}

// MARK: - 解析结果

/// 解析引擎输出：草稿列表 + 无法解析行的汇总提示（纯值类型，不触库）
struct ParseResult: Sendable {
    var drafts: [DraftEntry]
    var warnings: [String]

    init(drafts: [DraftEntry] = [], warnings: [String] = []) {
        self.drafts = drafts
        self.warnings = warnings
    }

    var isEmpty: Bool { drafts.isEmpty && warnings.isEmpty }
}

// MARK: - 导入来源

enum ImportSource: Sendable {
    /// 微信/文本粘贴内容
    case paste(String)
    /// 本地文件（按扩展名分发 Extractor：txt / docx / xlsx）
    case file(URL)
}

// MARK: - 提取输出

/// Extractor 统一输出：文本行 + 提取阶段警告（如合并单元格降级提示）
struct ExtractionOutput: Sendable {
    var lines: [String]
    var warnings: [String]

    static let empty = ExtractionOutput(lines: [], warnings: [])

    init(lines: [String] = [], warnings: [String] = []) {
        self.lines = lines
        self.warnings = warnings
    }
}
