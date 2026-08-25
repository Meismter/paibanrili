import SwiftUI

/// 微信粘贴输入页（R09）：TextEditor 粘贴区 + 示例占位文案 + 开始解析。
struct PasteInputView: View {

    @Bindable var viewModel: ImportViewModel
    /// 解析完成（无论有无结果）后的回调，由父视图决定后续跳转
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    private static let examplePlaceholder =
        """
        示例：
        3月5日 早班 张三
        3月5日 中 李四
        3月6日 夜 王五 / 休 赵六
        下周一 白班 我
        """

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("粘贴排班文字")
                .font(.headline)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.pasteText)
                    .frame(minHeight: 220)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.3))
                    )
                if viewModel.pasteText.isEmpty {
                    Text(Self.examplePlaceholder)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(14)
                        .allowsHitTesting(false)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button {
                Task {
                    await viewModel.parsePaste()
                    onFinished()
                }
            } label: {
                HStack {
                    if viewModel.isParsing {
                        ProgressView().tint(.white)
                    }
                    Text("开始解析")
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isParsing || trimmedInput.isEmpty)
        }
        .padding()
        .navigationTitle("微信粘贴")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
    }

    private var trimmedInput: String {
        viewModel.pasteText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
