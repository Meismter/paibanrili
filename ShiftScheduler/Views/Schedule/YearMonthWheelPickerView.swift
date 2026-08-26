import SwiftUI

/// 年月滚轮选择器（长按年月标题弹出）：
/// 左侧年份滚轮 + 右侧月份滚轮，确定后回调 (year, month)。
struct YearMonthWheelPickerView: View {

    /// 初始年份
    let initialYear: Int
    /// 初始月份 1...12
    let initialMonth: Int
    /// 确定回调
    let onConfirm: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    /// 年份候选：当前年前后各 12 年（覆盖 25 年跨度）
    private let yearRange = (Date().year - 12)...(Date().year + 12)
    private let months = Array(1...12)

    @State private var selectedYear: Int
    @State private var selectedMonth: Int

    init(initialYear: Int, initialMonth: Int, onConfirm: @escaping (Int, Int) -> Void) {
        self.initialYear = initialYear
        self.initialMonth = initialMonth
        self.onConfirm = onConfirm
        self._selectedYear = State(initialValue: initialYear)
        self._selectedMonth = State(initialValue: initialMonth)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    // 左：年份滚轮
                    Picker("年份", selection: $selectedYear) {
                        ForEach(yearRange, id: \.self) { year in
                            Text("\(String(year)) 年")
                                .tag(year)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    // 右：月份滚轮
                    Picker("月份", selection: $selectedMonth) {
                        ForEach(months, id: \.self) { month in
                            Text("\(month) 月")
                                .tag(month)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                }
                .frame(height: 220)
                .padding(.horizontal, 12)

                Text("跳转到 \(selectedYear)年\(selectedMonth)月")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("快速切换月份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        onConfirm(selectedYear, selectedMonth)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(360)])
    }
}
