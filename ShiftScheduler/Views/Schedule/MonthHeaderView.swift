import SwiftUI

/// 月份导航头（R01）：‹ 年月 › 切换 + 成员切换菜单。
struct MonthHeaderView: View {

    let monthTitle: String
    let members: [Member]
    let currentMember: Member?
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSelectMember: (Member) -> Void

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

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("下一月")

            memberMenu
        }
        .padding(.horizontal)
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
