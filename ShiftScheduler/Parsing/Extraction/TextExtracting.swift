import Foundation
import ZIPFoundation

// MARK: - 提取错误

enum ExtractionError: LocalizedError {
    case invalidContainer      // zip 容器无法打开
    case missingEntry(String)  // 缺少必需的内部文件
    case parseFailed(String)   // 内部 XML 解析失败

    var errorDescription: String? {
        switch self {
        case .invalidContainer:
            return "文件不是有效的压缩容器"
        case .missingEntry(let path):
            return "文件缺少内部资源：\(path)"
        case .parseFailed(let detail):
            return "内部结构解析失败：\(detail)"
        }
    }
}

// MARK: - 提取协议（架构 §3 TextExtracting）

/// 文本提取器协议：输入文件二进制 → 输出文本行。
/// 解析引擎只依赖本协议，Word/Excel 支持的增删不影响上游（架构 §6 零依赖降级路径）。
protocol TextExtracting {
    /// 支持的文件扩展名（小写、不含点），如 ["docx"]
    var supportedExtensions: [String] { get }

    /// 是否能处理该扩展名
    func canHandle(fileExtension: String) -> Bool

    /// 从文件数据中提取文本行
    func extract(data: Data) throws -> ExtractionOutput
}

extension TextExtracting {
    func canHandle(fileExtension: String) -> Bool {
        supportedExtensions.contains(fileExtension.lowercased())
    }
}

// MARK: - 提取器注册表

enum ExtractorRegistry {

    /// 全部内置提取器（顺序无关）
    static let all: [TextExtracting] = [
        TxtExtractor(),
        DocxExtractor(),
        XlsxExtractor()
    ]

    /// 按扩展名分发提取器
    static func extractor(for fileExtension: String) -> TextExtracting? {
        all.first { $0.canHandle(fileExtension: fileExtension) }
    }
}

// MARK: - Zip 内部读取工具（Docx/Xlsx 共用）

enum ZipReader {

    /// 从内存 zip 归档中按路径读取一个条目的完整数据
    static func readFile(_ archive: Archive, _ path: String) throws -> Data {
        guard let entry = archive[path] else {
            throw ExtractionError.missingEntry(path)
        }
        var data = Data()
        // bufferSize 取条目声明大小与默认值中较小者，避免超大条目一次性占用过多内存
        _ = try archive.extract(entry, skipCRC32: true) { chunk in
            data.append(chunk)
        }
        return data
    }

    /// 用给定 delegate 解析 XML 数据；失败抛出统一错误
    static func parseXML(_ data: Data, delegate: XMLParserDelegate, context: String) throws {
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            throw ExtractionError.parseFailed(context + ": " + (parser.parserError?.localizedDescription ?? "未知错误"))
        }
    }
}
