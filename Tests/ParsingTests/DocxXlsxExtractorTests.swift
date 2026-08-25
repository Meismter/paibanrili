import XCTest
import ZIPFoundation
@testable import ShiftScheduler

/// Docx / Xlsx 提取器测试。
///
/// 取舍声明（任务说明允许）：不随仓库附带二进制 fixture 文件，
/// 而是用 ZIPFoundation 在内存中编程构造最小合法的 .docx / .xlsx zip 结构
/// （仅包含提取器实际读取的条目），既覆盖 zip 解包路径，又保持测试自包含。
final class DocxXlsxExtractorTests: XCTestCase {

    // MARK: - 内存构造 zip 工具

    /// 构造只含指定条目的 zip 字节流（写入临时文件再读回，保证标准容器格式）
    private func makeZip(entries: [String: String]) throws -> Data {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let archive = try Archive(url: tempURL, accessMode: .create)
        for (path, content) in entries {
            let data = Data(content.utf8)
            try archive.addEntry(with: path,
                                 type: .file,
                                 uncompressedSize: data.count) { position, size in
                // ZIPFoundation provider 闭包签名：(Int64, Int) throws -> Data，需先收窄为 Int
                let start = Int(position)
                return data.subdata(in: start..<min(start + size, data.count))
            }
        }
        return try Data(contentsOf: tempURL)
    }

    private func writeTempFile(_ data: Data, ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).\(ext)")
        try? data.write(to: url)
        return url
    }

    // MARK: - Docx

    func testDocxExtractsParagraphLines() throws {
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>3月5日</w:t></w:r><w:r><w:t> 早班 张三</w:t></w:r></w:p>
            <w:p><w:r><w:t>3月6日 中 李四</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """
        let zipData = try makeZip(entries: ["word/document.xml": documentXML])
        let output = try DocxExtractor().extract(data: zipData)

        XCTAssertEqual(output.lines.count, 2)
        XCTAssertEqual(output.lines[0], "3月5日 早班 张三")
        XCTAssertEqual(output.lines[1], "3月6日 中 李四")
    }

    func testDocxInvalidContainerThrows() throws {
        XCTAssertThrowsError(try DocxExtractor().extract(data: Data("not a zip".utf8)))
    }

    // MARK: - Xlsx

    /// 构造最小 xlsx：共享字符串表 + sheet1 网格（布局 A：首行日期、行=人员）
    func testXlsxLayoutAPersonRowsDateColumns() throws {
        let sharedStrings = """
        <?xml version="1.0" encoding="UTF-8"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <si><t>张三</t></si><si><t>早</t></si><si><t>中</t></si>
          <si><t>李四</t></si><si><t>休</t></si><si><t>夜</t></si>
        </sst>
        """
        // 行1：姓名 | 3月1日 | 3月2日；行2：张三 | 早 | 中；行3：李四 | 休 | 夜
        let sheet = """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            <row r="1"><c r="A1"><v>姓名</v></c><c r="B1"><v>3月1日</v></c><c r="C1"><v>3月2日</v></c></row>
            <row r="2"><c r="A2" t="s"><v>0</v></c><c r="B2" t="s"><v>1</v></c><c r="C2" t="s"><v>2</v></c></row>
            <row r="3"><c r="A3" t="s"><v>3</v></c><c r="B3" t="s"><v>4</v></c><c r="C3" t="s"><v>5</v></c></row>
          </sheetData>
        </worksheet>
        """
        let zipData = try makeZip(entries: [
            "xl/sharedStrings.xml": sharedStrings,
            "xl/worksheets/sheet1.xml": sheet
        ])
        let output = try XlsxExtractor().extract(data: zipData)

        XCTAssertEqual(output.warnings, [])
        XCTAssertEqual(output.lines.count, 2)
        XCTAssertEqual(output.lines[0], "张三|3月1日=早|3月2日=中")
        XCTAssertEqual(output.lines[1], "李四|3月1日=休|3月2日=夜")
    }

    /// 布局 B：首列日期、列=人员（转置识别）
    func testXlsxLayoutBDateRowsPersonColumns() throws {
        let sheet = """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            <row r="1"><c r="A1"><v>日期</v></c><c r="B1"><v>张三</v></c></row>
            <row r="2"><c r="A2"><v>3月1日</v></c><c r="B2"><v>早</v></c></row>
            <row r="3"><c r="A3"><v>3月2日</v></c><c r="B3"><v>休</v></c></row>
          </sheetData>
        </worksheet>
        """
        let zipData = try makeZip(entries: ["xl/worksheets/sheet1.xml": sheet])
        let output = try XlsxExtractor().extract(data: zipData)

        XCTAssertEqual(output.lines.count, 1)
        XCTAssertEqual(output.lines[0], "张三|3月1日=早|3月2日=休")
    }

    /// 无日期表头 → 逐格文本降级并给出警告（架构假设 #2）
    func testXlsxFallbackToCellTextWhenNoDateHeader() throws {
        let sheet = """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            <row r="1"><c r="A1"><v>早</v></c><c r="B1"><v>中</v></c></row>
          </sheetData>
        </worksheet>
        """
        let zipData = try makeZip(entries: ["xl/worksheets/sheet1.xml": sheet])
        let output = try XlsxExtractor().extract(data: zipData)

        XCTAssertEqual(output.lines, ["早", "中"])
        XCTAssertTrue(output.warnings.contains { $0.contains("降级") })
    }

    func testColumnIndexParsing() {
        XCTAssertEqual(SheetXMLHandler.columnIndex(fromRef: "A1"), 0)
        XCTAssertEqual(SheetXMLHandler.columnIndex(fromRef: "B12"), 1)
        XCTAssertEqual(SheetXMLHandler.columnIndex(fromRef: "AA1"), 26)
    }

    // MARK: - 注册表与端到端（文件路径）

    func testRegistryDispatchesByExtension() {
        XCTAssertTrue(ExtractorRegistry.extractor(for: "txt") is TxtExtractor)
        XCTAssertTrue(ExtractorRegistry.extractor(for: "DOCX") is DocxExtractor)
        XCTAssertTrue(ExtractorRegistry.extractor(for: "xlsx") is XlsxExtractor)
        XCTAssertNil(ExtractorRegistry.extractor(for: "pdf"))
    }

    func testParseEngineReadsXlsxFromDiskFile() throws {
        let sharedStrings = "<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><si><t>早</t></si></sst>"
        // 行1=表头（姓名|3月1日），行2=张三数据（共享串"早" + 字面值"早"），
        // 保证布局 A 产出一条可解析行，使断言能真正捕获解析回归
        let sheet = """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            <row r="1"><c r="A1"><v>姓名</v></c><c r="B1"><v>3月1日</v></c></row>
            <row r="2"><c r="A2" t="s"><v>0</v></c><c r="B2"><v>早</v></c></row>
          </sheetData>
        </worksheet>
        """
        let zipData = try makeZip(entries: [
            "xl/sharedStrings.xml": sharedStrings,
            "xl/worksheets/sheet1.xml": sheet
        ])
        let url = writeTempFile(zipData, ext: "xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = ParseEngine(baseDate: date(2026, 3, 10))
        let result = engine.parseFile(at: url)
        // 强断言：端到端必须产出 1 条草稿，且日期/班次标签正确
        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertEqual(result.drafts[0].shiftLabel, "早")
        XCTAssertEqual(result.drafts[0].attributedDate, date(2026, 3, 1))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
