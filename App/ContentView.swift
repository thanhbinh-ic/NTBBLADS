import SwiftUI

struct ContentView: View {
    @StateObject private var store = FilterStore()
    @State private var showAddList = false
    @State private var showManualEditor = false
    @State private var newListName = ""
    @State private var newListURL = ""
    @State private var addError = ""

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Danh sách lọc")) {
                    ForEach(store.lists) { list in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.name)
                                    .font(.body)
                                Text(subtitle(for: list))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if list.isManual {
                                Button("Sửa") { showManualEditor = true }
                                    .buttonStyle(.bordered)
                            }
                            Toggle("", isOn: Binding(
                                get: { list.enabled },
                                set: { store.setEnabled(id: list.id, enabled: $0) }
                            ))
                            .labelsHidden()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !list.isManual {
                                Button(role: .destructive) { store.removeList(id: list.id) } label: {
                                    Label("Xóa", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Thêm list qua link") { showAddList = true }
                    Button("Cập nhật tất cả ngay") {
                        store.updateStaleLists(force: true) { failed in
                            if !failed.isEmpty {
                                store.status = "Không cập nhật được: " + failed.joined(separator: ", ")
                            }
                        }
                    }
                    .disabled(store.isWorking)
                }

                Section(header: Text("Trạng thái")) {
                    if store.isWorking {
                        ProgressView("Đang xử lý…")
                    }
                    Text("Đã áp dụng: \(store.appliedRules) luật")
                        .font(.footnote)
                    if store.truncatedCount > 0 {
                        Text("Đã bỏ \(store.truncatedCount) luật vì Safari chỉ cho tối đa 50.000 luật — tắt bớt danh sách lớn để đủ chỗ.")
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                    if !store.status.isEmpty {
                        Text(store.status)
                            .font(.footnote)
                            .foregroundColor(store.status.hasPrefix("Lỗi") || store.status.hasPrefix("Đã lưu nhưng") ? .red : .secondary)
                    }
                    Text("List đăng ký tự kiểm tra cập nhật mỗi 24 giờ khi mở app, và chạy nền khi iOS cho phép.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("CustomBlocker")
            .toolbar {
                Button("Hướng dẫn") { showHelp = true }
            }
            .sheet(isPresented: $showAddList) { addListSheet }
            .sheet(isPresented: $showManualEditor) {
                ManualEditorView(store: store)
            }
            .sheet(isPresented: $showHelp) { HelpView() }
            .onAppear {
                store.load()
                store.updateStaleLists()
                FilterStore.scheduleRefresh()
            }
        }
    }

    @State private var showHelp = false

    private func subtitle(for list: FilterList) -> String {
        var parts: [String] = []
        if list.isManual {
            parts.append("nhập tay")
        } else if let url = list.url, let host = URL(string: url)?.host {
            parts.append(host)
        }
        parts.append("\(list.ruleCount) luật")
        if list.skippedCount > 0 { parts.append("bỏ qua \(list.skippedCount)") }
        if let last = list.lastUpdated {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            parts.append("cập nhật \(formatter.string(from: last))")
        } else if !list.isManual {
            parts.append("chưa tải lần nào")
        }
        return parts.joined(separator: " • ")
    }

    private var addListSheet: some View {
        NavigationView {
            Form {
                TextField("Tên list (vd. ABPVN)", text: $newListName)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                TextField("Link list (https://…)", text: $newListURL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                if !addError.isEmpty {
                    Text(addError)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
                Text("List phải là file text theo cú pháp AdBlock/uBlock (EasyList, uBlock filters…). App tải về, dịch sang định dạng Safari rồi áp dụng.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .navigationTitle("Thêm list qua link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { showAddList = false; addError = "" }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Thêm") {
                        store.addSubscription(name: newListName, urlString: newListURL) { error in
                            if let error = error {
                                addError = error
                            } else {
                                newListName = ""
                                newListURL = ""
                                addError = ""
                                showAddList = false
                            }
                        }
                    }
                    .disabled(newListURL.isEmpty || store.isWorking)
                }
            }
        }
    }
}

struct ManualEditorView: View {
    @ObservedObject var store: FilterStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var errors: [String] = []

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .border(Color.secondary.opacity(0.4))
                    .padding(.horizontal)
                if !errors.isEmpty {
                    Text("Lỗi:\n" + errors.joined(separator: "\n"))
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                Spacer()
            }
            .navigationTitle("Bộ lọc của tôi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu & Áp dụng") {
                        let result = FilterEngine.build(from: text)
                        if !result.errors.isEmpty {
                            errors = result.errors
                            return
                        }
                        errors = []
                        store.saveManualText(text)
                        dismiss()
                    }
                }
            }
            .onAppear { text = store.manualText() }
        }
    }
}

struct HelpView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Bật extension")
                        .font(.headline)
                    Text("Cài đặt → Safari → Trình chặn nội dung (iOS 17 trở lên: Tiện ích mở rộng) → bật CustomBlocker. Sau đó quay lại app, nhập bộ lọc rồi bấm Lưu & Áp dụng.")
                    Text("List đăng ký")
                        .font(.headline)
                    Text("Mỗi list là một file bộ lọc trên mạng (EasyList, uBlock filters, ABPVN…). App tải về, dịch sang định dạng Safari rồi gộp với các list khác. Bật/tắt từng list bằng công tắc; vuốt sang trái để xóa list đã thêm. List tự kiểm tra cập nhật mỗi 24 giờ khi mở app, và chạy nền khi iOS cho phép (không đảm bảo giờ giấc — bấm Cập nhật tất cả ngay để chắc chắn).")
                    Text("Giới hạn 50.000 luật")
                        .font(.headline)
                    Text("Safari chỉ cho tối đa 50.000 luật trong một bộ lọc. App khử trùng rồi chia đều cho các list đang bật, whitelist luôn giữ hết và xếp cuối. Nếu vẫn vượt, app báo số luật đã bỏ — tắt bớt danh sách lớn (vd. HaGeZi) để đủ chỗ.")
                    Text("Cú pháp bộ lọc — mỗi dòng 1 luật")
                        .font(.headline)
                    Text("||quangcao.com — chặn mọi request tới domain + subdomain (chỉ third-party).\n||quangcao.com/banner — chặn URL có đường dẫn đó (cả first-party).\nquangcao.com — giống ||quangcao.com.\n##.ad-banner — ẩn phần tử theo selector CSS trên mọi trang.\nexample.com##.popup-ad — ẩn phần tử chỉ trên example.com.\n@@||quangcao.com — cho phép lại domain (đứng sau luật chặn).\n# ... hoặc ! ... — dòng ghi chú, bỏ qua.\nList đăng ký còn hiểu thêm $script, $image, $third-party, $domain=... và regex /.../. Các kiểu redirect, scriptlet, $popup, $badfilter thì Safari không diễn đạt được nên app bỏ qua.")
                        .font(.system(.body, design: .monospaced))
                }
                .padding()
            }
            .navigationTitle("Hướng dẫn")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
