import SwiftUI
import UniformTypeIdentifiers

struct JournalBackupScreen: View {
    @EnvironmentObject private var store: NotebookStore
    @Environment(\.scenePhase) private var phase
    @State private var recoveryCode = ""
    @State private var restoreCode = ""
    @State private var savedCode = false
    @State private var exportURL: URL?
    @State private var importURL: URL?
    @AppStorage("roam.backup.lastExport") private var lastExport = 0.0
    @State private var exporting = false
    @State private var importing = false
    @State private var imported: TravelNotebook?
    @State private var busy = false
    @State private var message: String?
    @State private var error: String?
    @State private var confirmRestore = false
    @State private var generation = UUID()
    @State private var work: Task<Void, Never>?
    var body: some View {
        Form {
            Section {
                Text("Back up all trips, notes, photos, flights, documents, packing items, and saved packing templates to an encrypted file. Restore on another device with its separate recovery code.")
                Button("Prepare encrypted backup", systemImage: "lock.doc") { prepareBackup() }.disabled(busy || store.isSaving || !store.isReady)
                if !recoveryCode.isEmpty {
                    Text("Recovery code").font(.headline)
                    Text(recoveryCode).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).privacySensitive()
                    Text("Keep this code in a safe place, separate from the backup file. Both are needed to restore. Roam Journal cannot recover a lost code.").font(.footnote).foregroundStyle(.secondary)
                    Toggle("I have saved the recovery code", isOn: $savedCode)
                    Button("Save backup to Files", systemImage: "square.and.arrow.up") { exporting = true }.disabled(!savedCode || exportURL == nil)
                }
            } header: { Text("Create backup") } footer: { Text("A new random recovery code is generated for each backup. It is not your Face ID or device passcode. Backup files contain encrypted data only.") }
            Section {
                SecureField("Backup recovery code", text: $restoreCode).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(busy)
                Button("Choose backup file", systemImage: "folder") { importing = true }.disabled(busy || store.isSaving || restoreCode.isEmpty)
                if let imported {
                    Text("Verified backup · \(imported.trips.count) trips · \(imported.trips.reduce(0) { $0 + $1.entries.count }) entries · \(imported.packingTemplates?.count ?? 0) templates")
                    Button("Restore as additional trips", systemImage: "arrow.counterclockwise") { confirmRestore = true }.disabled(busy || store.isSaving)
                }
            } header: { Text("Restore backup") } footer: { Text("Existing trips are kept. Restored trips receive new identities and will appear as additional trips; importing the same backup again creates duplicates. Requires Face ID. New backups stream up to 2 GB; older-format imports are limited to 250 MB.") }
            if lastExport > 0 { Section { LabeledContent("Last saved backup", value: Date(timeIntervalSince1970: lastExport).formatted(date: .abbreviated, time: .shortened)) } }
            if busy { Section { ProgressView("Working securely…") } }
            if let message { Section { Text(message).foregroundStyle(.secondary) } }
        }
        .navigationTitle("Backup & restore").navigationBarTitleDisplayMode(.inline)
        .fileMover(isPresented: $exporting, file: exportURL) { result in
            switch result {
            case .success: lastExport = Date.now.timeIntervalSince1970; message = "Backup saved. Keep its recovery code safe."; clearExport()
            case .failure(let error): self.error = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): readBackup(url)
            case .failure(let error): self.error = error.localizedDescription
            }
        }
        .confirmationDialog("Restore this backup as additional trips?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore trips") { restore() }
        } message: { Text("Your existing journal is kept. Restored copies are added and will sync if iCloud is enabled.") }
        .alert("Backup needs attention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .onChange(of: restoreCode) { _, _ in imported = nil }
        .onChange(of: phase) { _, value in if value == .background { clearSensitiveState() } }
        .onDisappear { clearSensitiveState() }
    }
    private func clearExport() { recoveryCode = ""; savedCode = false; if let exportURL { try? FileManager.default.removeItem(at: exportURL) }; exportURL = nil }
    private func clearSensitiveState() {
        generation = UUID(); work?.cancel(); work = nil; busy = false
        clearExport(); if let importURL { try? FileManager.default.removeItem(at: importURL) }; importURL = nil; restoreCode = ""; imported = nil; confirmRestore = false
    }
    private func prepareBackup() {
        clearExport(); message = nil; busy = true
        let token = UUID(); generation = token
        work = Task { @MainActor in
            defer { if generation == token { busy = false } }
            do {
                try await store.authorizeBackup()
                try Task.checkCancellation()
                let code = NotebookBackup.recoveryCode()
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("RoamJournal-" + UUID().uuidString + ".roambackup")
                do { try await store.exportBackup(code: code, to: url) } catch { try? FileManager.default.removeItem(at: url); throw error }
                guard !Task.isCancelled, generation == token else { try? FileManager.default.removeItem(at: url); return }
                recoveryCode = code; exportURL = url
            } catch { if generation == token, !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func readBackup(_ url: URL) {
        imported = nil; message = nil; busy = true
        let token = UUID(); generation = token; let code = restoreCode
        work = Task { @MainActor in
            defer { if generation == token { busy = false } }
            do {
                try await store.authorizeBackup()
                let result = try await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                    guard UInt64(size) <= StreamingBackup.maximumBytes else { throw BackupError.tooLarge }
                    let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".roambackup")
                    do {
                        try FileManager.default.copyItem(at: url, to: copy)
                        let book: TravelNotebook
                        if try StreamingBackup.isStreaming(copy) { book = try StreamingBackup.read(copy, code: code) }
                        else { guard size <= NotebookBackup.maximumBytes else { throw BackupError.tooLarge }; book = try NotebookBackup.open(Data(contentsOf: copy), code: code) }
                        return (book, copy)
                    } catch { try? FileManager.default.removeItem(at: copy); throw error }
                }.value
                guard !Task.isCancelled, generation == token else { try? FileManager.default.removeItem(at: result.1); return }
                imported = result.0; if let importURL { try? FileManager.default.removeItem(at: importURL) }; importURL = result.1
            } catch { if generation == token, !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func restore() {
        guard let importURL, imported != nil else { return }
        busy = true; let token = generation
        work = Task { @MainActor in
            defer { if generation == token { busy = false } }
            do {
                try await store.restoreBackupFile(importURL, code: restoreCode)
                if generation == token { self.imported = nil; restoreCode = ""; message = "Trips restored successfully. Existing trips were kept." }
            } catch { if generation == token { self.error = error.localizedDescription } }
        }
    }
}
