import Foundation
import ZIPFoundation

/// .docx 提取器（R07）。
/// .docx = zip 容器 + word/document.xml；用 Foundation XMLParser 做最小提取：
/// 收集所有 <w:t> 文本，遇 </w:p>（段落/表格单元格内段落边界）落为一行，线性拼接。
///
/// 取舍声明（架构假设 #3）：不做表格行/列结构还原与跨页合并单元格处理，
/// 单元格内文本按独立段落逐行输出；复杂排版建议用户另存为 TXT 兜底。
struct DocxExtractor: TextExtracting {

    let supportedExtensions = ["docx"]

    func extract(data: Data) throws -> ExtractionOutput {
        guard let archive = Archive(data: data, accessMode: .read) else {
            throw ExtractionError.invalidContainer
        }
        let xmlData = try ZipReader.readFile(archive, "word/document.xml")
        let handler = DocumentXMLHandler()
        try ZipReader.parseXML(xmlData, delegate: handler, context: "word/document.xml")
        return ExtractionOutput(lines: handler.lines, warnings: [])
    }
}

// MARK: - word/document.xml 解析委托

/// 最小 OOXML 文本收集器：
/// - <w:t> 内的字符累积为当前缓冲；
/// - </w:p> 时将缓冲落为一行（表格单元格内的 w:p 同样生效 → 线性拼接语义）。
private final class DocumentXMLHandler: NSObject, XMLParserDelegate {

    private(set) var lines: [String] = []
    private var buffer = ""
    private var insideText = false

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "w:t":
            insideText = true
        case "w:p":
            buffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideText {
            buffer += string
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "w:t":
            insideText = false
        case "w:p":
            flushLine()
        default:
            break
        }
    }

    private func flushLine() {
        let line = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.isEmpty {
            lines.append(line)
        }
        buffer = ""
    }
}
