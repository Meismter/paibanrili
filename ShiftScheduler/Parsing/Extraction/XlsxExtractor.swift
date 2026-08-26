import Foundation
import ZIPFoundation

/// .xlsx 提取器（R08）。
/// .xlsx = zip + xl/sharedStrings.xml（共享字符串表）+ xl/worksheets/sheet1.xml（首个工作表）。
///
/// 布局识别（架构假设 #2）：先构建单元格网格，再判定两种常见方向——
/// A：首行=日期表头、每行=人员（行=人员、列=日期）；B：首列=日期表头（行=日期、列=人员）。
/// 以"表头中可识别日期的数量"打分取高者；两者都不成立时降级为逐格文本输出。
/// 合并单元格不做结构还原，空格直接跳过（架构假设 #2 降级策略），并在警告中提示。
struct XlsxExtractor: TextExtracting {

    let supportedExtensions = ["xlsx"]

    private static let sharedStringsPath = "xl/sharedStrings.xml"
    private static let sheetPath = "xl/worksheets/sheet1.xml"

    func extract(data: Data) throws -> ExtractionOutput {
        // ZIPFoundation ≥0.9.17 的 Archive 初始化器为 throwing（非 failable），
        // 用 try? 保持原 guard-let 语义：非法容器 → invalidContainer。
        guard let archive = try? Archive(data: data) else {
            throw ExtractionError.invalidContainer
        }

        // 1) 共享字符串表（部分文件可能没有）
        var sharedStrings: [String] = []
        if archive[Self.sharedStringsPath] != nil {
            let stringsXML = try ZipReader.readFile(archive, Self.sharedStringsPath)
            let handler = SharedStringsHandler()
            try ZipReader.parseXML(stringsXML, delegate: handler, context: "sharedStrings")
            sharedStrings = handler.strings
        }

        // 2) 工作表网格
        let sheetXML = try ZipReader.readFile(archive, Self.sheetPath)
        let handler = SheetXMLHandler(sharedStrings: sharedStrings)
        try ZipReader.parseXML(sheetXML, delegate: handler, context: "sheet1")
        let grid = handler.grid
        guard !grid.isEmpty else {
            return ExtractionOutput(lines: [], warnings: ["工作表为空"])
        }

        // 3) 布局识别与文本行生成
        return Self.makeLines(from: grid)
    }

    // MARK: - 网格 → 文本行

    /// 将网格转换为解析引擎可读的文本行。
    /// 行格式："姓名|3月1日=早|3月2日=中"，日期与值之间用 '=' 连接，
    /// 字段间用 '|' 分隔，便于下游按分隔符切 token 后做日期/班次识别。
    static func makeLines(from grid: [[String]]) -> ExtractionOutput {
        let firstRowDateScore = dateLikeCount(in: grid.first ?? [])
        let firstColumnDateScore = dateLikeCount(in: grid.map { $0.first ?? "" })

        if firstRowDateScore >= firstColumnDateScore && firstRowDateScore > 0 {
            // 布局 A：行=人员、列=日期
            let headers = (grid.first ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            var lines: [String] = []
            for row in grid.dropFirst() {
                guard let name = row.first(where: { !$0.isEmpty }) else { continue }
                var fields = [name]
                for (index, header) in headers.enumerated() where index > 0 {
                    let cell = index < row.count ? row[index] : ""
                    if !cell.isEmpty && !header.isEmpty {
                        fields.append("\(header)=\(cell)")
                    }
                }
                if fields.count > 1 {
                    lines.append(fields.joined(separator: "|"))
                }
            }
            return ExtractionOutput(lines: lines, warnings: mergeCellWarningIfNeeded(grid))
        }

        if firstColumnDateScore > 0 {
            // 布局 B：行=日期、列=人员；按"列"重组为每人一行
            let rowCount = grid.count
            let columnCount = grid.map(\.count).max() ?? 0
            var lines: [String] = []
            for col in 1..<max(columnCount, 1) {
                var name = ""
                var fields: [String] = []
                for row in 0..<rowCount where col < grid[row].count {
                    let cell = grid[row][col]
                    if row == 0 {
                        name = cell // 首行同列为人员名
                        continue
                    }
                    let dateHeader = grid[row].first ?? ""
                    if !cell.isEmpty && !dateHeader.isEmpty {
                        fields.append("\(dateHeader)=\(cell)")
                    }
                }
                if name.isEmpty { name = "人员\(col)" }
                if !fields.isEmpty {
                    lines.append(([name] + fields).joined(separator: "|"))
                }
            }
            return ExtractionOutput(lines: lines, warnings: mergeCellWarningIfNeeded(grid))
        }

        // 降级：逐格文本（架构假设 #2 极端合并单元格场景）
        let lines = grid.flatMap { row in
            row.filter { !$0.isEmpty }
        }
        return ExtractionOutput(
            lines: lines,
            warnings: ["未识别出日期表头，已按逐格文本降级提取，请在预览页人工核对"]
        )
    }

    // MARK: - Private

    /// 一组表头单元格中"像日期"的数量（复用 DateRecognizer 判定）
    private static func dateLikeCount(in cells: [String]) -> Int {
        cells.reduce(0) { count, cell in
            DateRecognizer.findDates(in: cell).isEmpty ? count : count + 1
        }
    }

    private static func mergeCellWarningIfNeeded(_ grid: [[String]]) -> [String] {
        // 行长不一致往往意味着存在合并单元格
        let lengths = Set(grid.map(\.count))
        return lengths.count > 1 ? ["检测到行长不一致（可能存在合并单元格），已跳过空白格"] : []
    }
}

// MARK: - xl/sharedStrings.xml 解析

/// 收集每个 <si> 条目的全部 <t> 文本（富文本多段拼接）
final class SharedStringsHandler: NSObject, XMLParserDelegate {

    private(set) var strings: [String] = []
    private var buffer = ""

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "si" {
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName == "si" {
            strings.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
            buffer = ""
        }
    }
}

// MARK: - xl/worksheets/sheet1.xml 解析

/// 构建 [row][col] 字符串网格：
/// - <c r="B2" t="s"><v>3</v></c>：t="s" 表示 <v> 是共享字符串索引；
/// - t 缺省时 <v> 为字面值（数字/文本）；
/// - t="inlineStr" 时取 <is><t>…</t></is> 内联文本。
final class SheetXMLHandler: NSObject, XMLParserDelegate {

    private let sharedStrings: [String]
    private(set) var grid: [[String]] = []

    // 当前解析状态机
    private var currentRow: [String] = []
    private var currentColumnIndex = 0
    private var currentType = ""
    private var valueBuffer = ""     // <v> 或内联 <t> 的原始字符累积
    private var sealedValue = ""     // 已闭合的 <v>/<t> 内容
    private var insideInlineText = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "row":
            currentRow = []
        case "c":
            currentColumnIndex = Self.columnIndex(fromRef: attributeDict["r"] ?? "")
            currentType = attributeDict["t"] ?? ""
            valueBuffer = ""
            sealedValue = ""
        case "t":
            if currentType == "inlineStr" {
                insideInlineText = true
                valueBuffer = ""
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        valueBuffer += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "v":
            sealedValue = valueBuffer
            valueBuffer = ""
        case "t":
            if insideInlineText {
                sealedValue = valueBuffer
                valueBuffer = ""
                insideInlineText = false
            }
        case "c":
            padRow(toInclude: currentColumnIndex)
            currentRow[currentColumnIndex] = resolvedCellValue()
            currentType = ""
            sealedValue = ""
            valueBuffer = ""
        case "row":
            grid.append(currentRow)
            currentRow = []
        default:
            break
        }
    }

    // MARK: - Private

    /// 将共享字符串索引 / 字面值 / 内联文本统一解析为展示字符串
    private func resolvedCellValue() -> String {
        let trimmed = sealedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if currentType == "s", let index = Int(trimmed), sharedStrings.indices.contains(index) {
            return sharedStrings[index]
        }
        return trimmed
    }

    /// 补齐行长度到指定索引（跳过的空单元格补 ""，模拟稀疏网格）
    private func padRow(toInclude index: Int) {
        while currentRow.count <= max(index, 0) {
            currentRow.append("")
        }
    }

    /// "B12" → 列索引 1（A=0）；无字母前缀时返回 0
    static func columnIndex(fromRef ref: String) -> Int {
        let letters = ref.prefix { $0.isLetter }
        guard !letters.isEmpty else { return 0 }
        var index = 0
        for letter in letters.uppercased().unicodeScalars {
            guard letter.value >= 65, letter.value <= 90 else { continue }
            index = index * 26 + Int(letter.value - 64)
        }
        return max(index - 1, 0)
    }
}
