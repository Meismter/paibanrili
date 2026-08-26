import SwiftUI

/// 月份导航头（R01）：‹ 年月 › 切换 + 成员切换菜单。
/// 长按"xxxx年x月"标题可调出快速切换月份菜单（当年 12 个月 / 切换年份 / 回到今天）。
struct MonthHeaderView: View {

    let monthTitle: String
    /// 当前显示年份（用于构建长按菜单的月份列表）
    let displayedYear: Int
    /// 当前显示月份 1...12（用于菜单勾选标记）
    let displayedMonthNumber: Int
    let members: [Member]
    let currentMember: Member?
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSelectMember: (Member) -> Void
    /// 长按菜单：跳转到当前显示年的某月（1...12）
    var onPickMonth: (Int) -> Void = { _ in }
    /// 长按菜单：切换到某一年（保持当前月份）
    var onPickYear: (Int) -> Void = { _ in }
    /// 长按菜单：回到今天所在月份
    var onBackToToday: () -> Void = {}

    private var currentYear: Int { Date().year }

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("上一月")

            Text(monthTitle)
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .contextMenu { quickJumpMenu }
                .accessibilityHint("长按可快速切换月份")

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("下一月")

            memberMenu
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 8)
    }

    // MARK: - 长按快速切换菜单

    @ViewBuilder
    private var quickJumpMenu: some View {
        Button {
            onBackToToday()
        } label: {
            Label("回到今天", systemImage: "calendar.badge.clock")
        }

        Section("\(String(displayedYear))年") {
            ForEach(1...12, id: \.self) { month in
                Button {
                    onPickMonth(month)
                } label: {
                    if month == displayedMonthNumber {
                        Label("\(month)月", systemImage: "checkmark")
                    } else {
                        Text("\(month)月")
                    }
                }
            }
        }

        Section("切换年份") {
            ForEach(yearOptions, id: \.self) { year in
                Button {
                    onPickYear(year)
                } label: {
                    if year == displayedYear {
                        Label("\(String(year))年", systemImage: "checkmark")
                    } else {
                        Text(year == currentYear ? "今年（\(String(year))年）" : "\(String(year))年")
                    }
                }
            }
        }
    }

    /// 年份候选：当前显示年前后各 5 年
    private var yearOptions: [Int] {
        Array((displayedYear - 5)...(displayedYear + 5))
    }

    private var memberMenu: some View {
        Menu {
            ForEach(members) { member in
                Button {
                    onSelectMember(member)
                } label: {
                    Label(member.name,
                          systemImage: member.id == currentMember?.id ? "checkmark" : "person")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                Text(currentMember?.name ?? "成员")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary, in: Capsule())
        }
    }
}
