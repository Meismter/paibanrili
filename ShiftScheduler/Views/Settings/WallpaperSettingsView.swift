import SwiftUI
import PhotosUI

/// 壁纸设置（批次 A）：每 Tab 一个分区 —— 内置壁纸色块网格 / 相册选图 /
/// 透明度与缩放滑杆 / 恢复默认。透明度与缩放即时生效（@Observable 管理）。
struct WallpaperSettingsView: View {

    @State private var manager = WallpaperManager.shared
    /// 各 Tab 正在选择的相册项（一次仅处理一个）
    @State private var pickerItems: [WallpaperTab: PhotosPickerItem] = [:]

    var body: some View {
        List {
            ForEach(WallpaperTab.allCases) { tab in
                Section {
                    builtinGrid(for: tab)
                        .listRowBackground(Color.clear)
                    PhotosPicker(selection: photoBinding(for: tab),
                                 matching: .images) {
                        Label("从相册选择图片", systemImage: "photo.on.rectangle")
                    }
                    .listRowBackground(Color.clear)
                    controls(for: tab)
                        .listRowBackground(Color.clear)
                    Button("恢复默认", role: .destructive) {
                        manager.reset(for: tab)
                    }
                    .listRowBackground(Color.clear)
                } header: {
                    Label(tab.displayName, systemImage: tab.iconName)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
        .navigationTitle("壁纸设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 内置壁纸网格

    @ViewBuilder
    private func builtinGrid(for tab: WallpaperTab) -> some View {
        let current = manager.selectionID(for: tab)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                  spacing: 10) {
            // 默认（无壁纸）
            swatch(gradient: LinearGradient(colors: [Color(uiColor: .systemGray5), Color(uiColor: .systemGray6)],
                                            startPoint: .top, endPoint: .bottom),
                   name: "默认",
                   selected: current == 0) {
                manager.setSelectionID(0, for: tab)
            }
            ForEach(WallpaperManager.builtins) { builtin in
                swatch(gradient: builtin.gradient,
                       name: builtin.name,
                       selected: current == builtin.id) {
                    manager.setSelectionID(builtin.id, for: tab)
                }
            }
        }
    }

    private func swatch(gradient: LinearGradient,
                        name: String,
                        selected: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(gradient)
                    .frame(height: 40)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selected ? Color.accentColor : Color.gray.opacity(0.25),
                                    lineWidth: selected ? 2.5 : 1)
                    }
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 相册选图

    private func photoBinding(for tab: WallpaperTab) -> Binding<PhotosPickerItem?> {
        Binding(
            get: { pickerItems[tab] },
            set: { item in
                guard let item else {
                    pickerItems[tab] = nil
                    return
                }
                pickerItems[tab] = item
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        manager.setPhoto(image, for: tab)
                    }
                }
            }
        )
    }

    // MARK: - 透明度 / 缩放

    @ViewBuilder
    private func controls(for tab: WallpaperTab) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("透明度")
                Slider(value: Binding(get: { manager.opacity(for: tab) },
                                      set: { manager.setOpacity($0, for: tab) }),
                       in: 0.2...1.0)
            }
            HStack {
                Text("缩放")
                Slider(value: Binding(get: { manager.scale(for: tab) },
                                      set: { manager.setScale($0, for: tab) }),
                       in: 0.5...2.0)
            }
        }
        .padding(.vertical, 2)
    }
}
