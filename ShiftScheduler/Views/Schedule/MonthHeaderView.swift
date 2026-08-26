import SwiftUI

/// 月份导航头（R01）：‹ 年月 › 切换 + 成员切换菜单。
/// 长按"xxxx年x月"标题弹出滚轮选择器（左年右月）快速跳转月份。
struct MonthHeaderView: View {

    let monthTitle: String
    /// 当前显示年份（滚轮选择器初值）
    let displayedYear: Int
    /// 当前显示月份 1...12（滚轮选择器初值）
    let displayedMonthNumber: Int
    let members: [Member]
    let currentMember: Member?
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSelectMember: (Member) -> Void
    /// 长按标题 → 由父视图弹出年月滚轮选择器
    var onLongPressTitle: () -> Void = {}

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
                .onLongPressGesture(minimumDuration: 0.35) {
                    onLongPressTitle()
                }
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
