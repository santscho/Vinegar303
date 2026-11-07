import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

private enum Vinegar303PresetContentType {
    static let preset = UTType(filenameExtension: Vinegar303Preset.fileExtension) ?? .json
    static let category = UTType(filenameExtension: Vinegar303PresetCategoryArchive.fileExtension) ?? .json
    static let all = [preset, category]
}

// MARK: - Compact browser

/// The fast browser embedded in the SEQUENCER header. Full management lives in
/// the separate manager sheet.
struct Vinegar303PresetBrowser: View {
    @ObservedObject var presets: Vinegar303PresetController
    @Binding var showingManager: Bool

    @State private var pendingOffset: Int?
    @State private var alert: PresetBrowserAlert?

    private var isFactory: Bool {
        presets.currentEntry.isFactory
    }

    var body: some View {
        HStack(spacing: 7) {
            Text("PRESET")
                .font(Vinegar303Theme.monoSmall)
                .tracking(1.2)
                .foregroundStyle(Vinegar303Theme.faint)

            HStack(spacing: 1) {
                stepButton("chevron.left") {
                    requestStep(-1)
                }

                HStack(spacing: 3) {
                    Text(presets.currentEntry.name)
                        .font(Vinegar303Theme.readout)
                        .foregroundStyle(isFactory ? Vinegar303Theme.dim : Vinegar303Theme.acid)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if isFactory {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(Vinegar303Theme.faint)
                    }
                    if presets.isDirty {
                        Circle()
                            .fill(Vinegar303Theme.amber)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(width: 148, alignment: .leading)
                .help("\(presets.currentEntry.category) · \(presets.currentEntry.scope.detail)")

                stepButton("chevron.right") {
                    requestStep(1)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Vinegar303Theme.border, lineWidth: 1)
            )

            Button {
                do {
                    try presets.saveCurrent()
                } catch {
                    alert = .error(error.localizedDescription)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 8, weight: .semibold))
                    Text("SAVE")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                }
                .foregroundStyle(isFactory ? Vinegar303Theme.faint : Vinegar303Theme.dim)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Vinegar303Theme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isFactory || !presets.isDirty)
            .opacity(isFactory || !presets.isDirty ? 0.45 : 1)
            .help(isFactory ? "Factory Default is read-only — use Manage to Save As" : "Save preset")

            Button {
                showingManager = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 8, weight: .semibold))
                    Text("MANAGE")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                }
                .foregroundStyle(Vinegar303Theme.dim)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Vinegar303Theme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Open the preset manager")
        }
        .alert(item: $alert) { item in
            switch item {
            case .discard(let offset):
                return Alert(
                    title: Text("Discard unsaved changes?"),
                    message: Text("Loading another preset will replace the current unsaved edits."),
                    primaryButton: .destructive(Text("Discard")) {
                        load(offset: offset)
                    },
                    secondaryButton: .cancel {
                        pendingOffset = nil
                    }
                )
            case .error(let message):
                return Alert(
                    title: Text("Preset Error"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func requestStep(_ offset: Int) {
        if presets.isDirty {
            pendingOffset = offset
            alert = .discard(offset)
        } else {
            load(offset: offset)
        }
    }

    private func load(offset: Int) {
        do {
            try presets.step(offset)
        } catch {
            alert = .error(error.localizedDescription)
        }
        pendingOffset = nil
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Vinegar303Theme.dim)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private enum PresetBrowserAlert: Identifiable {
    case discard(Int)
    case error(String)

    var id: String {
        switch self {
        case .discard(let offset): "discard-\(offset)"
        case .error(let message): "error-\(message)"
        }
    }
}

// MARK: - Manager

private struct PresetManagerNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct PresetImportRequest {
    let urls: [URL]
    let category: String
    let conflicts: [Vinegar303PresetImportConflict]
}

struct Vinegar303PresetManagerView: View {
    @ObservedObject var presets: Vinegar303PresetController
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: String
    @State private var selectedEntryID: String?
    @State private var saveName: String
    @State private var saveCategory: String
    @State private var saveScope: Vinegar303PresetScope
    @State private var renameName = ""
    @State private var newCategoryName = ""
    @State private var isAddingCategory = false
    @State private var renameCategoryName = ""
    @State private var isRenamingCategory = false
    @State private var showingCopyPatterns = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDocument: Vinegar303PresetExportDocument?
    @State private var exportName = "Preset.v303preset"
    @State private var notice: PresetManagerNotice?
    @State private var deleteCandidate: Vinegar303PresetEntry?
    @State private var deleteCategoryCandidate: String?
    @State private var pendingImport: PresetImportRequest?

    init(presets: Vinegar303PresetController) {
        _presets = ObservedObject(wrappedValue: presets)
        let current = presets.currentEntry
        let category = current.isFactory
            ? Vinegar303PresetLibrary.defaultCategoryName
            : current.category
        _selectedCategory = State(initialValue: current.category)
        _selectedEntryID = State(initialValue: current.id)
        _saveName = State(initialValue: current.isFactory ? "New Preset" : "\(current.name) Copy")
        _saveCategory = State(initialValue: category)
        _saveScope = State(initialValue: current.scope)
    }

    private var writableCategories: [Vinegar303PresetCategory] {
        presets.categories.filter { !$0.isFactory }
    }

    private var selectedEntry: Vinegar303PresetEntry? {
        guard let selectedEntryID else { return nil }
        return presets.entries.first { $0.id == selectedEntryID }
    }

    private var categoryEntries: [Vinegar303PresetEntry] {
        presets.entries.filter { $0.category == selectedCategory }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Vinegar303Theme.border)
            HStack(spacing: 0) {
                categorySidebar
                    .frame(width: 190)
                Divider().overlay(Vinegar303Theme.border)
                presetList
                    .frame(width: 270)
                Divider().overlay(Vinegar303Theme.border)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider().overlay(Vinegar303Theme.border)
            footer
        }
        .frame(width: 900, height: 570)
        .background(Vinegar303Theme.background)
        .preferredColorScheme(.dark)
        .onAppear {
            presets.refreshLibrary()
            reconcileSelection()
        }

        .sheet(isPresented: $showingCopyPatterns) {
            Vinegar303PatternCopyView(
                presets: presets,
                selectedEntry: selectedEntry
            )
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: Vinegar303PresetContentType.all,
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: exportDocument?.contentType ?? Vinegar303PresetContentType.preset,
            defaultFilename: exportName
        ) { result in
            if case .failure(let error) = result {
                notice = PresetManagerNotice(title: "Export Failed", message: error.localizedDescription)
            }
        }
        .confirmationDialog(
            "Delete preset?",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteSelected()
            }
            Button("Cancel", role: .cancel) {
                deleteCandidate = nil
            }
        } message: {
            Text(deleteCandidate?.name ?? "")
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PRESET MANAGER")
                    .font(Vinegar303Theme.label)
                    .tracking(1.6)
                    .foregroundStyle(Vinegar303Theme.text)
                Text("FILE-BACKED PRESETS · CATEGORIES · PATTERN COPY")
                    .font(Vinegar303Theme.monoSmall)
                    .tracking(1.0)
                    .foregroundStyle(Vinegar303Theme.faint)
            }

            Spacer()

            Button {
                showingImporter = true
            } label: {
                managerButtonLabel("IMPORT", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.plain)
            .help("Import presets into the selected category or restore a category file")
            .confirmationDialog(
                "Import conflict",
                isPresented: Binding(
                    get: { pendingImport != nil },
                    set: { if !$0 { pendingImport = nil } }
                )
            ) {
                Button("SKIP") {
                    resolveImport(.skip)
                }
                Button("KEEP BOTH") {
                    resolveImport(.keepBoth)
                }
                Button("OVERWRITE EXISTING", role: .destructive) {
                    resolveImport(.overwrite)
                }
            } message: {
                Text(importConflictMessage)
            }

            Button("CLOSE") {
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(Vinegar303Theme.dim)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Vinegar303Theme.border, lineWidth: 1)
            )
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(Color.black.opacity(0.24))
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(presets.library.isSharedLibrary ? Vinegar303Theme.acid : Vinegar303Theme.amber)
                .frame(width: 4, height: 4)
            Text(presets.library.isSharedLibrary ? "SHARED PRESET LIBRARY" : "LOCAL PRESET LIBRARY")
                .font(Vinegar303Theme.monoSmall)
                .tracking(0.9)
                .foregroundStyle(Vinegar303Theme.dim)
            Text("·")
                .foregroundStyle(Vinegar303Theme.faint)
            Text(presets.library.libraryURL.path)
                .font(Vinegar303Theme.monoSmall)
                .foregroundStyle(Vinegar303Theme.faint)
                .lineLimit(1)
                .truncationMode(.middle)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([presets.library.libraryURL])
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 8, weight: .semibold))
                    Text("SHOW IN FINDER")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                }
                .foregroundStyle(Vinegar303Theme.dim)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Vinegar303Theme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Show the preset library in Finder")

            Spacer(minLength: 10)

            Text("\(presets.entries.count) PRESETS")
                .font(Vinegar303Theme.monoSmall)
                .tracking(0.8)
                .foregroundStyle(Vinegar303Theme.faint)
        }
        .padding(.horizontal, 18)
        .frame(height: 32)
        .background(Color.black.opacity(0.24))
    }

    // MARK: Categories

    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CATEGORIES")
                    .font(Vinegar303Theme.monoSmall)
                    .tracking(1.2)
                    .foregroundStyle(Vinegar303Theme.faint)
                Spacer()
                Button {
                    isAddingCategory.toggle()
                    isRenamingCategory = false
                    renameCategoryName = ""
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Vinegar303Theme.dim)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Create a category")
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(presets.categories) { category in
                        categoryRow(category)
                    }
                }
            }

            Button {
                exportCategory(selectedCategory)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 8, weight: .semibold))
                    Text("EXPORT CATEGORY")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                    Spacer(minLength: 3)
                    Text("\(categoryEntries.count)")
                        .font(Vinegar303Theme.monoSmall)
                }
                .foregroundStyle(categoryEntries.isEmpty ? Vinegar303Theme.faint : Vinegar303Theme.dim)
                .padding(.horizontal, 7)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Vinegar303Theme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(categoryEntries.isEmpty)
            .opacity(categoryEntries.isEmpty ? 0.45 : 1)
            .help("Export every preset in the selected category as one file")

            Button {
                renameCategoryName = selectedCategory
                isRenamingCategory.toggle()
                isAddingCategory = false
                newCategoryName = ""
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "pencil")
                        .font(.system(size: 8, weight: .semibold))
                    Text("RENAME CATEGORY")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                    Spacer(minLength: 3)
                }
                .foregroundStyle(
                    selectedCategory == Vinegar303PresetLibrary.factoryCategoryName
                        ? Vinegar303Theme.faint
                        : Vinegar303Theme.dim
                )
                .padding(.horizontal, 7)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Vinegar303Theme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedCategory == Vinegar303PresetLibrary.factoryCategoryName)
            .opacity(selectedCategory == Vinegar303PresetLibrary.factoryCategoryName ? 0.45 : 1)
            .help("Rename the selected user category")

            if isRenamingCategory {
                VStack(spacing: 5) {
                    TextField("Category name", text: $renameCategoryName)
                        .textFieldStyle(.plain)
                        .font(Vinegar303Theme.monoSmall)
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.black.opacity(0.35))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Vinegar303Theme.border, lineWidth: 1)
                        )
                    HStack(spacing: 5) {
                        Button("RENAME") {
                            renameCategory()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Vinegar303Theme.acid)
                        Button("CANCEL") {
                            isRenamingCategory = false
                            renameCategoryName = ""
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Vinegar303Theme.faint)
                    }
                }
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                )
            }

            Button {
                deleteCategoryCandidate = selectedCategory
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "trash")
                        .font(.system(size: 8, weight: .semibold))
                    Text("DELETE CATEGORY")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                    Spacer(minLength: 3)
                }
                .foregroundStyle(
                    selectedCategory == Vinegar303PresetLibrary.factoryCategoryName
                        ? Vinegar303Theme.faint
                        : Vinegar303Theme.amber
                )
                .padding(.horizontal, 7)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Vinegar303Theme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedCategory == Vinegar303PresetLibrary.factoryCategoryName)
            .opacity(selectedCategory == Vinegar303PresetLibrary.factoryCategoryName ? 0.45 : 1)
            .help("Delete the selected category and all presets inside it")
            .confirmationDialog(
                "Delete category?",
                isPresented: Binding(
                    get: { deleteCategoryCandidate != nil },
                    set: { if !$0 { deleteCategoryCandidate = nil } }
                )
            ) {
                Button("DELETE", role: .destructive) {
                    deleteSelectedCategory()
                }
                Button("CANCEL", role: .cancel) {
                    deleteCategoryCandidate = nil
                }
            } message: {
                Text(categoryDeleteWarning)
            }

            if isAddingCategory {
                VStack(spacing: 5) {
                    TextField("Category name", text: $newCategoryName)
                        .textFieldStyle(.plain)
                        .font(Vinegar303Theme.monoSmall)
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.black.opacity(0.35))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Vinegar303Theme.border, lineWidth: 1)
                        )
                    HStack(spacing: 5) {
                        Button("CREATE") {
                            createCategory()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Vinegar303Theme.acid)
                        Button("CANCEL") {
                            isAddingCategory = false
                            newCategoryName = ""
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Vinegar303Theme.faint)
                    }
                }
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                )
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.black.opacity(0.10))
    }

    private func categoryRow(_ category: Vinegar303PresetCategory) -> some View {
        Button {
            selectCategory(category.name)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: category.isFactory ? "lock.fill" : "folder")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(category.isFactory ? Vinegar303Theme.amber : Vinegar303Theme.faint)
                Text(category.name)
                    .font(Vinegar303Theme.readout)
                    .foregroundStyle(
                        selectedCategory == category.name
                            ? Vinegar303Theme.acid
                            : Vinegar303Theme.text
                    )
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(category.count)")
                    .font(Vinegar303Theme.monoSmall)
                    .foregroundStyle(Vinegar303Theme.faint)
            }
            .padding(.horizontal, 7)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        selectedCategory == category.name
                            ? Vinegar303Theme.acid.opacity(0.10)
                            : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Preset list

    private var presetList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PRESETS")
                    .font(Vinegar303Theme.monoSmall)
                    .tracking(1.2)
                    .foregroundStyle(Vinegar303Theme.faint)
                Spacer()
                Text("\(categoryEntries.count)")
                    .font(Vinegar303Theme.monoSmall)
                    .foregroundStyle(Vinegar303Theme.faint)
            }

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(categoryEntries) { entry in
                        presetRow(entry)
                    }
                }
            }

            if categoryEntries.isEmpty {
                Text("NO PRESETS IN THIS CATEGORY")
                    .font(Vinegar303Theme.monoSmall)
                    .tracking(0.6)
                    .foregroundStyle(Vinegar303Theme.faint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 24)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white.opacity(0.008))
    }

    private func presetRow(_ entry: Vinegar303PresetEntry) -> some View {
        Button {
            selectedEntryID = entry.id
            renameName = entry.name
        } label: {
            HStack(spacing: 7) {
                Image(systemName: entry.isFactory ? "lock.fill" : "waveform")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(entry.isFactory ? Vinegar303Theme.amber : Vinegar303Theme.faint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(Vinegar303Theme.readout)
                        .foregroundStyle(
                            selectedEntryID == entry.id
                                ? Vinegar303Theme.acid
                                : Vinegar303Theme.text
                        )
                        .lineLimit(1)
                    Text(entry.scope.title)
                        .font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Vinegar303Theme.faint)
                }
                Spacer(minLength: 4)
                if entry.id == presets.currentEntry.id {
                    Circle()
                        .fill(Vinegar303Theme.acid)
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        selectedEntryID == entry.id
                            ? Vinegar303Theme.acid.opacity(0.10)
                            : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Detail

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let entry = selectedEntry {
                    selectedPresetDetail(entry)
                } else {
                    Text("SELECT A PRESET")
                        .font(Vinegar303Theme.monoSmall)
                        .foregroundStyle(Vinegar303Theme.faint)
                }

                Divider().overlay(Vinegar303Theme.border)

                saveAsForm
            }
            .padding(18)
        }
    }

    private func selectedPresetDetail(_ entry: Vinegar303PresetEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Vinegar303Theme.text)
                if entry.isFactory {
                    Text("FACTORY")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Vinegar303Theme.amber)
                }
                Spacer()
                Text(entry.scope.title)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Vinegar303Theme.acid)
            }

            Text("\(entry.category) · \(entry.scope.detail)")
                .font(Vinegar303Theme.monoSmall)
                .foregroundStyle(Vinegar303Theme.faint)

            HStack(spacing: 7) {
                actionButton("LOAD", systemImage: "play.fill") {
                    loadSelected(entry)
                }
                actionButton("DUPLICATE", systemImage: "plus.square.on.square") {
                    duplicate(entry)
                }
                actionButton("COPY PATTERNS", systemImage: "arrow.left.arrow.right") {
                    selectedEntryID = entry.id
                    showingCopyPatterns = true
                }
                actionButton("EXPORT", systemImage: "square.and.arrow.up") {
                    export(entry)
                }
                if !entry.isFactory {
                    actionButton("DELETE", systemImage: "trash", destructive: true) {
                        deleteCandidate = entry
                    }
                }
            }

            if !entry.isFactory {
                HStack(spacing: 6) {
                    TextField("Rename preset", text: $renameName)
                        .textFieldStyle(.plain)
                        .font(Vinegar303Theme.readout)
                        .padding(.horizontal, 7)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.black.opacity(0.35))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Vinegar303Theme.border, lineWidth: 1)
                        )
                    Button("RENAME") {
                        rename(entry)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Vinegar303Theme.dim)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                }
            }
        }
    }

    private var saveAsForm: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("SAVE CURRENT AS")
                .font(Vinegar303Theme.monoSmall)
                .tracking(1.2)
                .foregroundStyle(Vinegar303Theme.faint)

            HStack(spacing: 7) {
                TextField("Preset name", text: $saveName)
                    .textFieldStyle(.plain)
                    .font(Vinegar303Theme.readout)
                    .padding(.horizontal, 7)
                    .frame(height: 27)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Vinegar303Theme.border, lineWidth: 1)
                    )

                Picker("", selection: $saveCategory) {
                    ForEach(writableCategories) { category in
                        Text(category.name).tag(category.name)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
            }

            Picker("", selection: $saveScope) {
                ForEach(Vinegar303PresetScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Button("SAVE CURRENT AS") {
                saveCurrentAs()
            }
            .buttonStyle(.plain)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(Color.black)
            .padding(.horizontal, 11)
            .frame(height: 27)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Vinegar303Theme.acid)
            )
        }
    }

    // MARK: Actions

    private func selectCategory(_ category: String) {
        selectedCategory = category
        selectedEntryID = presets.entries(in: category).first?.id
        isRenamingCategory = false
        renameCategoryName = ""
        if category != Vinegar303PresetLibrary.factoryCategoryName {
            saveCategory = category
        }
    }

    private func reconcileSelection() {
        if !presets.categories.contains(where: { $0.name == selectedCategory }) {
            selectedCategory = presets.currentEntry.isFactory
                ? Vinegar303PresetLibrary.factoryCategoryName
                : presets.currentEntry.category
        }

        if selectedEntryID == nil || presets.entries.first(where: { $0.id == selectedEntryID }) == nil {
            selectedEntryID = presets.entries(in: selectedCategory).first?.id
        }
        if let selectedEntry {
            renameName = selectedEntry.name
        } else {
            renameName = ""
        }
        if !writableCategories.contains(where: { $0.name == saveCategory }),
           let first = writableCategories.first {
            saveCategory = first.name
        }
    }

    private func loadSelected(_ entry: Vinegar303PresetEntry) {
        guard !presets.isDirty else {
            notice = PresetManagerNotice(
                title: "Unsaved Changes",
                message: "Save or discard the active preset's changes before loading another preset."
            )
            return
        }
        do {
            try presets.load(entry)
            selectedCategory = entry.category
            selectedEntryID = entry.id
        } catch {
            notice = PresetManagerNotice(title: "Load Failed", message: error.localizedDescription)
        }
    }

    private func saveCurrentAs() {
        do {
            let saved = try presets.saveAs(
                name: saveName,
                category: saveCategory,
                scope: saveScope
            )
            selectedCategory = saved.category
            selectedEntryID = saved.id
            saveName = "\(saved.name) Copy"
            renameName = saved.name
        } catch {
            notice = PresetManagerNotice(title: "Save Failed", message: error.localizedDescription)
        }
    }

    private func createCategory() {
        do {
            let category = try presets.createCategory(newCategoryName)
            selectedCategory = category
            saveCategory = category
            newCategoryName = ""
            isAddingCategory = false
            isRenamingCategory = false
            renameCategoryName = ""
        } catch {
            notice = PresetManagerNotice(title: "Category", message: error.localizedDescription)
        }
    }

    private func renameCategory() {
        let oldCategory = selectedCategory
        let selectedName = selectedEntry?.name
        do {
            let renamed = try presets.renameCategory(oldCategory, to: renameCategoryName)
            if saveCategory == oldCategory {
                saveCategory = renamed
            }
            selectedCategory = renamed
            selectedEntryID = selectedName.flatMap { name in
                presets.entries(in: renamed).first {
                    $0.name.caseInsensitiveCompare(name) == .orderedSame
                }?.id
            } ?? presets.entries(in: renamed).first?.id
            renameCategoryName = ""
            isRenamingCategory = false
        } catch {
            notice = PresetManagerNotice(
                title: "Category Rename Failed",
                message: error.localizedDescription
            )
        }
    }

    private func duplicate(_ entry: Vinegar303PresetEntry) {
        do {
            let copy = try presets.duplicate(entry)
            selectedCategory = copy.category
            selectedEntryID = copy.id
            saveName = "\(copy.name) Copy"
            renameName = copy.name
        } catch {
            notice = PresetManagerNotice(title: "Duplicate Failed", message: error.localizedDescription)
        }
    }

    private func rename(_ entry: Vinegar303PresetEntry) {
        do {
            let renamed = try presets.rename(entry, to: renameName)
            selectedEntryID = renamed.id
            saveName = "\(renamed.name) Copy"
        } catch {
            notice = PresetManagerNotice(title: "Rename Failed", message: error.localizedDescription)
        }
    }

    private func deleteSelected() {
        guard let candidate = deleteCandidate else { return }
        do {
            try presets.delete(candidate)
            selectedEntryID = presets.entries(in: selectedCategory).first?.id
        } catch {
            notice = PresetManagerNotice(title: "Delete Failed", message: error.localizedDescription)
        }
        deleteCandidate = nil
    }

    private var categoryDeleteWarning: String {
        guard let category = deleteCategoryCandidate else { return "" }
        let count = presets.entries(in: category).count
        if count == 0 {
            return "“\(category)” will be permanently deleted. This cannot be undone."
        }
        let contents = count == 1 ? "its 1 preset" : "all \(count) presets it contains"
        return "“\(category)” will be permanently deleted with \(contents). This cannot be undone."
    }

    private func deleteSelectedCategory() {
        guard let category = deleteCategoryCandidate else { return }
        do {
            _ = try presets.deleteCategory(category)
            selectedCategory = presets.currentEntry.isFactory
                ? Vinegar303PresetLibrary.factoryCategoryName
                : presets.currentEntry.category
            selectedEntryID = presets.entries(in: selectedCategory).first?.id
            reconcileSelection()
        } catch {
            notice = PresetManagerNotice(title: "Delete Failed", message: error.localizedDescription)
        }
        deleteCategoryCandidate = nil
    }

    private func export(_ entry: Vinegar303PresetEntry) {
        do {
            exportDocument = Vinegar303PresetExportDocument(preset: try presets.library.preset(for: entry))
            exportName = "\(entry.name).\(Vinegar303Preset.fileExtension)"
            showingExporter = true
        } catch {
            notice = PresetManagerNotice(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func exportCategory(_ category: String) {
        do {
            let archive = try presets.categoryArchive(for: category)
            exportDocument = Vinegar303PresetExportDocument(category: archive)
            exportName = "\(category).\(Vinegar303PresetCategoryArchive.fileExtension)"
            showingExporter = true
        } catch {
            notice = PresetManagerNotice(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private var importConflictMessage: String {
        guard let pendingImport else { return "" }
        let items = pendingImport.conflicts.map { conflict in
            switch conflict.kind {
            case .category:
                "category “\(conflict.name)”"
            case .preset:
                "preset “\(conflict.name)” in “\(conflict.category)”"
            }
        }
        let exists = pendingImport.conflicts.count == 1 ? "already exists" : "already exist"
        let subject = pendingImport.conflicts.count == 1
            ? "The \(items[0]) \(exists)."
            : "The following \(exists): \(items.joined(separator: ", "))."
        let hasCategoryConflict = pendingImport.conflicts.contains { $0.kind == .category }
        let replaced = hasCategoryConflict
            ? "the existing category and all of its presets"
            : "the existing preset"
        let untouched = pendingImport.conflicts.count == 1 ? "it" : "them"
        return "\(subject) SKIP leaves \(untouched) untouched. KEEP BOTH imports a copy with a “version” suffix. OVERWRITE EXISTING replaces \(replaced)."
    }

    private func resolveImport(_ policy: Vinegar303PresetImportPolicy) {
        guard let request = pendingImport else { return }
        pendingImport = nil
        performImport(request.urls, into: request.category, policy: policy)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let selectedTarget = selectedCategory == Vinegar303PresetLibrary.factoryCategoryName
                ? saveCategory
                : selectedCategory
            let target = writableCategories.contains { $0.name == selectedTarget }
                ? selectedTarget
                : (writableCategories.first?.name ?? Vinegar303PresetLibrary.defaultCategoryName)
            do {
                let conflicts = try presets.importConflicts(from: urls, into: target)
                if conflicts.isEmpty {
                    performImport(urls, into: target, policy: .keepBoth)
                } else {
                    pendingImport = PresetImportRequest(
                        urls: urls,
                        category: target,
                        conflicts: conflicts
                    )
                }
            } catch {
                notice = PresetManagerNotice(title: "Import Failed", message: error.localizedDescription)
            }
        case .failure(let error):
            notice = PresetManagerNotice(title: "Import Failed", message: error.localizedDescription)
        }
    }

    private func performImport(
        _ urls: [URL],
        into target: String,
        policy: Vinegar303PresetImportPolicy
    ) {
        do {
            let imported = try presets.importPresets(urls, into: target, policy: policy)
            guard !imported.isEmpty else {
                notice = PresetManagerNotice(
                    title: "Import Skipped",
                    message: "No presets were imported."
                )
                return
            }
            if let first = imported.first {
                selectedCategory = first.category
                selectedEntryID = first.id
                saveCategory = first.category
                saveName = "\(first.name) Copy"
                renameName = first.name
            }
        } catch {
            notice = PresetManagerNotice(title: "Import Failed", message: error.localizedDescription)
        }
    }

    // MARK: Controls

    private func managerButtonLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .semibold))
            Text(title)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.7)
        }
        .foregroundStyle(Vinegar303Theme.dim)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Vinegar303Theme.border, lineWidth: 1)
        )
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .semibold))
                Text(title)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundStyle(destructive ? Vinegar303Theme.amber : Vinegar303Theme.dim)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Vinegar303Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pattern copy

struct Vinegar303PatternCopyView: View {
    @ObservedObject var presets: Vinegar303PresetController
    @Environment(\.dismiss) private var dismiss

    @State private var sourceID: String
    @State private var destinationID: String
    @State private var sourcePattern: Int
    @State private var destinationPattern: Int
    @State private var notice: PresetManagerNotice?

    init(presets: Vinegar303PresetController, selectedEntry: Vinegar303PresetEntry?) {
        _presets = ObservedObject(wrappedValue: presets)

        let source = selectedEntry ?? presets.currentEntry
        let destination = presets.entries.first {
            !$0.isFactory && $0.id != source.id
        } ?? presets.entries.first { !$0.isFactory }

        _sourceID = State(initialValue: source.id)
        _destinationID = State(initialValue: destination?.id ?? "")
        _sourcePattern = State(initialValue: 0)
        _destinationPattern = State(initialValue: 0)
    }

    private var writableEntries: [Vinegar303PresetEntry] {
        presets.entries.filter { !$0.isFactory }
    }

    private var sourceEntry: Vinegar303PresetEntry? {
        presets.entries.first { $0.id == sourceID }
    }

    private var destinationEntry: Vinegar303PresetEntry? {
        presets.entries.first { $0.id == destinationID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("COPY PATTERNS")
                        .font(Vinegar303Theme.label)
                        .tracking(1.6)
                        .foregroundStyle(Vinegar303Theme.text)
                    Text("PATTERN DATA AND LENGTH · DESTINATION SOUND SETTINGS STAY INTACT")
                        .font(Vinegar303Theme.monoSmall)
                        .tracking(0.6)
                        .foregroundStyle(Vinegar303Theme.faint)
                }
                Spacer()
                Button("CLOSE") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Vinegar303Theme.dim)
            }

            Divider().overlay(Vinegar303Theme.border)

            if writableEntries.isEmpty {
                Text("Create a user preset before copying patterns.")
                    .font(Vinegar303Theme.readout)
                    .foregroundStyle(Vinegar303Theme.faint)
            } else {
                copyForm(
                    title: "SOURCE",
                    entries: presets.entries,
                    selection: $sourceID,
                    pattern: $sourcePattern
                )

                copyForm(
                    title: "DESTINATION",
                    entries: writableEntries,
                    selection: $destinationID,
                    pattern: $destinationPattern
                )

                HStack(spacing: 8) {
                    Button("COPY PATTERN") {
                        copyPatterns(all: false)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 11)
                    .frame(height: 27)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Vinegar303Theme.acid)
                    )

                    Button("COPY ALL 16") {
                        copyPatterns(all: true)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Vinegar303Theme.dim)
                    .padding(.horizontal, 11)
                    .frame(height: 27)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Vinegar303Theme.border, lineWidth: 1)
                    )

                    Spacer()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 590, height: 380)
        .background(Vinegar303Theme.background)
        .preferredColorScheme(.dark)
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func copyForm(
        title: String,
        entries: [Vinegar303PresetEntry],
        selection: Binding<String>,
        pattern: Binding<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Vinegar303Theme.monoSmall)
                .tracking(1.1)
                .foregroundStyle(Vinegar303Theme.faint)

            HStack(spacing: 7) {
                Picker("", selection: selection) {
                    ForEach(entries) { entry in
                        Text("\(entry.category) / \(entry.name)")
                            .tag(entry.id)
                    }
                }
                .labelsHidden()

                Picker("", selection: pattern) {
                    ForEach(0..<Vinegar303PatternLibrary.patternCount, id: \.self) { index in
                        Text(String(format: "%02d", index + 1))
                            .tag(index)
                    }
                }
                .labelsHidden()
                .frame(width: 72)
            }
        }
    }

    private func copyPatterns(all: Bool) {
        guard let sourceEntry, let destinationEntry else {
            notice = PresetManagerNotice(title: "Copy Failed", message: "Choose a source and destination preset.")
            return
        }

        do {
            let indices: [Int] = all
                ? Array(0..<Vinegar303PatternLibrary.patternCount)
                : [sourcePattern]
            let start = all ? 0 : destinationPattern
            _ = try presets.copyPatterns(
                from: sourceEntry,
                sourcePatterns: indices,
                to: destinationEntry,
                destinationStart: start
            )
            dismiss()
        } catch {
            notice = PresetManagerNotice(title: "Copy Failed", message: error.localizedDescription)
        }
    }
}

// MARK: - Export document

struct Vinegar303PresetExportDocument: FileDocument {
    enum Content {
        case preset(Vinegar303Preset)
        case category(Vinegar303PresetCategoryArchive)
    }

    static var readableContentTypes: [UTType] {
        Vinegar303PresetContentType.all
    }

    var content: Content

    init(preset: Vinegar303Preset) {
        content = .preset(preset)
    }

    init(category: Vinegar303PresetCategoryArchive) {
        content = .category(category)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw Vinegar303PresetError.invalidDocument("The exported file is empty.")
        }

        struct FormatProbe: Decodable {
            let format: String
        }
        let format = try JSONDecoder().decode(FormatProbe.self, from: data).format
        switch format {
        case Vinegar303Preset.formatIdentifier:
            content = .preset(try Vinegar303Preset.decode(data))
        case Vinegar303PresetCategoryArchive.formatIdentifier:
            content = .category(try Vinegar303PresetCategoryArchive.decode(data))
        default:
            throw Vinegar303PresetError.invalidDocument("Unsupported export document.")
        }
    }

    var contentType: UTType {
        switch content {
        case .preset:
            Vinegar303PresetContentType.preset
        case .category:
            Vinegar303PresetContentType.category
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data: Data
        switch content {
        case .preset(let preset):
            data = try preset.encoded()
        case .category(let archive):
            data = try archive.encoded()
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
