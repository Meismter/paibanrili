import SwiftUI
import SwiftData

/// 成员管理页：成员列表（色点 + 名字），点击编辑（改名 + 12 色板选色），
/// 工具栏加号添加新成员，滑动删除（"我自己"禁删）。
/// 从设置页 NavigationLink 进入，样式遵循玻璃风（透明 List + 无行背景）。
struct MemberManagementView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = MemberManagementViewModel()

    @State private var editingMember: Member?
    @State private var editName = ""
    @State private var editColorHex = ""
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        List {
            ForEach(viewModel.members) { member in
                Button {
                    beginEditing(member)
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(member.colorHex.map { Color(paletteHex: $0) } ?? Color.gray)
                            .frame(width: 16, height: 16)
                        Text(member.name)
                            .foregroundStyle(.primary)
                        if member.isSelf {
                            Text("我自己")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
            .onDelete(perform: deleteMembers)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle("成员管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addNewMember()
                } label: {
                    Label("添加成员", systemImage: "plus")
                }
            }
        }
        .onAppear { viewModel.load(context: modelContext) }
        .sheet(item: $editingMember) { member in
            editSheet(for: member)
        }
        .alert("提示", isPresented: $showAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - 动作

    private func addNewMember() {
        guard let member = viewModel.addMember(name: "新成员",
                                               colorHex: Theme.palette[0].hex,
                                               context: modelContext) else {
            alertMessage = viewModel.lastMessage ?? "添加失败"
            showAlert = true
            return
        }
        editName = member.name
        editColorHex = member.colorHex ?? Theme.palette[0].hex
        editingMember = member
    }

    private func beginEditing(_ member: Member) {
        editName = member.name
        editColorHex = member.colorHex ?? Theme.palette[0].hex
        editingMember = member
    }

    private func deleteMembers(at offsets: IndexSet) {
        for index in offsets {
            let member = viewModel.members[index]
            if !viewModel.deleteMember(member: member, context: modelContext) {
                alertMessage = viewModel.lastMessage ?? "不能删除「我自己」成员"
                showAlert = true
            }
        }
    }

    private func saveEditing(_ member: Member) {
        viewModel.updateMember(member: member,
                               name: editName,
                               colorHex: editColorHex,
                               context: modelContext)
        editingMember = nil
        if let message = viewModel.lastMessage {
            alertMessage = message
            showAlert = true
        }
    }

    // MARK: - 编辑 Sheet

    private func editSheet(for member: Member) -> some View {
        NavigationStack {
            Form {
                Section("姓名") {
                    TextField("成员姓名", text: $editName)
                        .listRowBackground(Color.clear)
                }
                Section("标识色") {
                    ColorPaletteView(selectedHex: $editColorHex)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("编辑成员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { editingMember = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveEditing(member) }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview("成员管理") {
    NavigationStack {
        MemberManagementView()
    }
    .modelContainer(for: Member.self)
}
