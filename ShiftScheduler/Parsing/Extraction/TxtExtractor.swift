import Foundation

/// TXT / 粘贴文本提取器（R07/R09 兜底入口，零依赖零风险）。
/// 按换行切分为文本行；优先 UTF-8 解码，失败降级为有损解码，不抛错。
struct TxtExtractor: TextExtracting {

    let supportedExtensions = ["txt", "text", "log"]

    func extract(data: Data) throws -> ExtractionOutput {
        let text: String
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else if let gbk = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))) {
            // 常见中文环境导出为 GB 编码的兜底
            text = gbk
        } else {
            text = String(decoding: data, as: UTF8.self)
        }
        return ExtractionOutput(lines: Self.splitLines(text), warnings: [])
    }

    /// 统一按 \r\n / \n / \r 切行并去首尾空白、丢弃空行
    static func splitLines(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
