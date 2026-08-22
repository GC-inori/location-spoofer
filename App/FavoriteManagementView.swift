import SwiftUI
import CoreLocation

struct FavoriteManagementView: View {
    @ObservedObject var favorites: FavoriteLocationStore
    var onSelectAndReturnToMap: ((FavoriteLocation) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var expandedGroupIds: Set<UUID> = []
    @State private var showAddGroupAlert = false
    @State private var newGroupName = ""
    @State private var showDeleteGroupConfirmation = false
    @State private var groupToDelete: FavoriteGroup?
    @State private var selectedDetailLocation: FavoriteLocation?
    @State private var showSuccessToast = false
    @State private var copiedToastMessage = ""

    var body: some View {
        ZStack {
            List {
                ForEach(favorites.groups) { group in
                    Section {
                        if expandedGroupIds.contains(group.id) {
                            let locs = favorites.locations(in: group.id)
                            if locs.isEmpty {
                                Text("暂无收藏定位点")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 4)
                            } else {
                                ForEach(locs) { loc in
                                    locationRow(loc)
                                }
                                .onDelete { indexSet in
                                    deleteLocations(at: indexSet, in: group.id)
                                }
                                .onMove { indices, newOffset in
                                    favorites.moveLocations(inGroupId: group.id, from: indices, to: newOffset)
                                }
                            }
                        }
                    } header: {
                        groupHeaderView(group)
                    }
                }
                .onMove { indices, newOffset in
                    favorites.moveGroups(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.inactive))

            // 设置成功 Toast 提示
            if showSuccessToast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.teal)
                        Text("已设为当前定位")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                    .padding(.bottom, 36)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // 复制坐标 Toast
            if !copiedToastMessage.isEmpty {
                VStack {
                    Spacer()
                    Text(copiedToastMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.8), in: Capsule())
                        .padding(.bottom, 60)
                }
                .transition(.opacity)
            }
        }
        .navigationTitle("收藏管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    newGroupName = ""
                    showAddGroupAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .alert("新增分组", isPresented: $showAddGroupAlert) {
            TextField("分组名称 (最多10字)", text: $newGroupName)
            Button("创建") {
                let trimmed = String(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10))
                if !trimmed.isEmpty {
                    let group = favorites.addGroup(name: trimmed)
                    expandedGroupIds.insert(group.id)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请输入分组名称，例如「打卡常用」、「常去地点」等。")
        }
        .confirmationDialog(
            "确认删除分组「\(groupToDelete?.name ?? "")」？",
            isPresented: $showDeleteGroupConfirmation,
            titleVisibility: .visible
        ) {
            Button("连同组内坐标一起删除", role: .destructive) {
                if let group = groupToDelete {
                    favorites.deleteGroup(group.id)
                }
                groupToDelete = nil
            }
            Button("取消", role: .cancel) {
                groupToDelete = nil
            }
        } message: {
            Text("删除该分组将连带清空组内所有收藏坐标，此操作不可撤销。")
        }
        .sheet(item: $selectedDetailLocation) { loc in
            LocationDetailSheet(location: loc, onCopy: { message in
                showCopyToast(message)
            })
        }
    }

    // MARK: - 分组头部

    private func groupHeaderView(_ group: FavoriteGroup) -> some View {
        let isExpanded = expandedGroupIds.contains(group.id)
        let count = favorites.locations(in: group.id).count

        return HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if isExpanded {
                        expandedGroupIds.remove(group.id)
                    } else {
                        expandedGroupIds.insert(group.id)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(group.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("(\(count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if group.isDefault {
                        Text("默认")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.teal.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.teal)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // 只有非默认分组，或有多个分组时才允许删除
            if !group.isDefault || favorites.groups.count > 1 {
                Menu {
                    Button(role: .destructive) {
                        groupToDelete = group
                        showDeleteGroupConfirmation = true
                    } label: {
                        Label("删除分组", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
            }
        }
    }

    // MARK: - 单个定位项

    private func locationRow(_ loc: FavoriteLocation) -> some View {
        HStack {
            Button {
                applyLocation(loc)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(loc.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if let address = loc.fullAddress, !address.isEmpty {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            // 详情按钮 ⓘ
            Button {
                selectedDetailLocation = loc
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func deleteLocations(at indexSet: IndexSet, in groupId: UUID) {
        let groupLocs = favorites.locations(in: groupId)
        for index in indexSet where index < groupLocs.count {
            favorites.delete(groupLocs[index])
        }
    }

    private func applyLocation(_ loc: FavoriteLocation) {
        favorites.incrementUsageCount(id: loc.id)
        favorites.select(loc.id)

        // 触觉反馈
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)

        withAnimation(.easeInOut(duration: 0.2)) {
            showSuccessToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation {
                showSuccessToast = false
            }
            dismiss()
            onSelectAndReturnToMap?(loc)
        }
    }

    private func showCopyToast(_ msg: String) {
        withAnimation {
            copiedToastMessage = msg
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation {
                copiedToastMessage = ""
            }
        }
    }
}

// MARK: - 详情弹窗

struct LocationDetailSheet: View {
    let location: FavoriteLocation
    var onCopy: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("地点名称") {
                    Text(location.name)
                        .font(.headline)
                }

                Section("详细地址") {
                    Text(location.fullAddress ?? "暂无详细街道信息")
                        .font(.subheadline)
                        .foregroundStyle(location.fullAddress != nil ? .primary : .secondary)
                }

                Section("坐标信息 (长按复制)") {
                    coordinateRow(title: "国内标准 (GCJ-02)", coordText: String(format: "%.6f, %.6f", location.coordinatePair.gcj02.latitude, location.coordinatePair.gcj02.longitude))
                    coordinateRow(title: "国际标准 (WGS-84)", coordText: String(format: "%.6f, %.6f", location.coordinatePair.wgs84.latitude, location.coordinatePair.wgs84.longitude))
                }

                Section("使用统计") {
                    HStack {
                        Text("累计使用次数")
                        Spacer()
                        Text("\(location.usageCount) 次")
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("创建时间")
                        Spacer()
                        Text(location.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("定位详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func coordinateRow(title: String, coordText: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(coordText)
                    .font(.body.monospaced())
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    UIPasteboard.general.string = coordText
                    onCopy?("已复制 \(title) 坐标")
                    let feedback = UIImpactFeedbackGenerator(style: .light)
                    feedback.impactOccurred()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.footnote)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture {
            UIPasteboard.general.string = coordText
            onCopy?("已复制 \(title) 坐标")
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.impactOccurred()
        }
        .padding(.vertical, 2)
    }
}