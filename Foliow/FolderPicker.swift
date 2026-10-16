import SwiftUI
import UniformTypeIdentifiers

struct FolderPicker: UIViewControllerRepresentable {
    let selected: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let selected: (URL) -> Void
        init(selected: @escaping (URL) -> Void) { self.selected = selected }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { selected(url) }
        }
    }
}

struct AlbumPicker: View {
    @EnvironmentObject private var store: ReviewStore
    @Environment(\.dismiss) private var dismiss
    @State private var albums: [LibraryCollection] = []
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Group {
                if let error {
                    ContentUnavailableView("Photos access needed", systemImage: "photo.badge.exclamationmark", description: Text(error))
                } else if albums.isEmpty {
                    ProgressView("Opening your albums…")
                } else {
                    List(albums) { album in
                        Button {
                            Task { await store.importCollection(album); dismiss() }
                        } label: {
                            Label(album.title, systemImage: album.collection == nil ? "photo.stack" : "rectangle.stack")
                                .padding(.vertical, 8)
                        }.disabled(store.busy)
                    }
                }
            }
            .navigationTitle("Choose an album")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.busy) } }
            .interactiveDismissDisabled(store.busy)
            .task {
                do { try await PhotoService.authorize(); albums = PhotoService.collections() }
                catch { self.error = error.localizedDescription }
            }
        }
    }
}
