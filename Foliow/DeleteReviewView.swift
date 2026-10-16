import SwiftUI

struct DeleteReviewView: View {
    @EnvironmentObject private var store: ReviewStore
    @Environment(\.dismiss) private var dismiss
    let snapshot: [PhotoItem]
    @State private var confirm = false
    private var isLibrary: Bool { snapshot.first?.origin == .library }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("\(snapshot.count) original photo\(snapshot.count == 1 ? "" : "s")", systemImage: "trash")
                        .font(.headline).foregroundStyle(Palette.pass)
                    Text(isLibrary
                         ? "These passed photos will be deleted from your Photos library and synced iCloud Photos devices. Apple will also ask you to allow deletion. Normally you can recover them in Photos → Recently Deleted for 30 days."
                         : "These passed originals will be removed from the folder you selected, including subfolders. File deletion may be permanent; recovery depends on your file provider. You cannot undo deletion inside Foliow.")
                        .font(.subheadline)
                    Text("Keepers and unreviewed photos stay in their original place.")
                        .font(.caption).foregroundStyle(Palette.muted)
                } header: { Text("Review before deleting") }
                Section {
                    ForEach(snapshot) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.subheadline)
                            if let path = item.relativePath { Text(path).font(.caption2).foregroundStyle(.secondary) }
                        }.padding(.vertical, 3)
                    }
                } header: { Text("Only these passed photos") }
                Section {
                    Button(role: .destructive) { confirm = true } label: {
                        HStack { Spacer(); Label("Delete \(snapshot.count) passed originals", systemImage: "trash"); Spacer() }.padding(.vertical, 8)
                    }.disabled(store.busy || snapshot.isEmpty)
                }
            }
            .navigationTitle("Delete passed photos?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.busy) } }
            .interactiveDismissDisabled(store.busy)
            .overlay { if store.busy { ProgressView("Deleting passed photos…").padding(25).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15)) } }
            .alert("Delete \(snapshot.count) originals?", isPresented: $confirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete originals", role: .destructive) {
                    Task { await store.deleteConfirmed(snapshot); dismiss() }
                }
            } message: {
                Text(isLibrary ? "This changes your Photos library. Deleted assets normally go to Recently Deleted." : "This removes the actual passed files from the selected folder. This cannot be undone in Foliow.")
            }
        }
    }
}
