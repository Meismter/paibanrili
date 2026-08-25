import SwiftUI
import UniformTypeIdentifiers

/// 导入来源选择页（R07/R08/R09）：Word / Excel / TXT 文件选择器 + 微信文本粘贴。
struct ImportSourceView: View {

    // MARK: - 状态

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ImportViewModel()

    @State private var showFileImporter = false
    /// 待选择的文件类型（点击入口时设定）
    @State private var pendingFileKind: FileKind?
    @State private var showPasteSheet = false
    @State private var showPreview = false
    @State private var showResultAlert = false
    @State private var resultMessage = ""

    // MARK: - 文件类型

    private enum FileKind: String {
        case docx = "Word 文档"
        case xlsx = "Excel 表格"
        case txt  = "TXT 文本"

        var contentTypes: [UTType] {
            switch self {
            case .docx:
                return [UTType(filenameExtension: "docx") ?? .data]
            case .xlsx:
                return [UTType(filenameExtension: "xlsx") ?? .data]
            case .txt:
                return [.plainText, .text, UTType(filenameExtension: "txt") ?? .text]
            }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            Text("导入排班")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            VStack(spacing: 12) {
                sourceButton(icon: "doc.fill", title: "Word 文档", subtitle: "导入 .docx 排班表") {
                    pendingFileKind = .docx
                    showFileImporter = true
                }
                sourceButton(icon: "tablecells.fill", title: "Excel 表格", subtitle: "导入 .xlsx 排班矩阵") {
                    pendingFileKind = .xlsx
                    showFileImporter = true
                }
                sourceButton(icon: "doc.plaintext.fill", title: "TXT 文本", subtitle: "导入纯文本排班表") {
                    pendingFileKind = .txt
                    showFileImporter = true
                }
                sourceButton(icon: "bubble.left.and.bubble.right.fill",
                             title: "微信粘贴",
                             subtitle: "粘贴群里的排班文字消息") {
                    showPasteSheet = true
                }
            }
            .padding(.horizontal)

            if viewModel.isParsing {
                ProgressView("正在解析…")
                    .padding()
            }

            Spacer()
        }
        .padding(.top)
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: pendingFileKind?.contentTypes ?? [.data],
                      allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            Task {
                await viewModel.parseFile(at: url)
                presentPreviewIfNeeded()
            }
        }
        .sheet(isPresented: $showPasteSheet) {
            NavigationStack {
                PasteInputView(viewModel: viewModel) {
                    showPasteSheet = false
                    presentPreviewIfNeeded()
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showPreview) {
            NavigationStack {
                PreviewConfirmView(viewModel: viewModel) {
                    showPreview = false
                } onFailure: { message in
                    showPreview = false
                    resultMessage = message
                    showResultAlert = true
                }
            }
        }
        .alert("提示", isPresented: $showResultAlert) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(resultMessage)
        }
    }

    // MARK: - 子视图与动作

    private func sourceButton(icon: String,
                              title: String,
                              subtitle: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func presentPreviewIfNeeded() {
        if !viewModel.drafts.isEmpty {
            showPreview = true
        }
    }
}
