import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var store: ReviewStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showFolder = false
    @State private var showAlbums = false
    @State private var showHelp = false
    @State private var showDeletion = false
    @State private var deletionSnapshot: [PhotoItem] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                VStack(spacing: 18) {
                    heading
                    if store.session != nil {
                        Picker("Review section", selection: Binding(get: { store.filter }, set: store.setFilter)) {
                            ForEach(ReviewFilter.allCases) { filter in
                                Text(filterLabel(filter)).tag(filter)
                            }
                        }.pickerStyle(.segmented).disabled(store.busy)
                        if store.needsFolderAccess {
                            VStack(spacing: 10) {
                                Label("Reconnect your photo folder", systemImage: "folder.badge.questionmark")
                                Text("Reselect the original folder to restore access and your saved decisions.").font(.caption).foregroundStyle(Palette.muted)
                                Button("Choose original folder") { showFolder = true }.buttonStyle(.borderedProminent)
                            }.padding().background(.white, in: RoundedRectangle(cornerRadius: 16))
                        }
                        if let current = store.current {
                            ReviewCard(item: current)
                                .frame(maxHeight: .infinity)
                            decisionBar
                        } else {
                            completed
                        }
                        if !store.passed.isEmpty {
                            Button(role: .destructive) {
                                deletionSnapshot = store.passed
                                showDeletion = true
                            } label: {
                                Label("Review & delete \(store.passed.count) passed", systemImage: "trash")
                                    .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 10)
                            }.buttonStyle(.bordered).disabled(store.busy || store.needsFolderAccess)
                        }
                        progress
                    } else { welcome }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
                if store.busy {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView("Working…").padding(25).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .navigationTitle("foliow.")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }.accessibilityLabel("How it works")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Choose a Files folder", systemImage: "folder") { showFolder = true }
                        Button("Choose a Photos album", systemImage: "photo.on.rectangle") { showAlbums = true }
                    } label: { Image(systemName: "plus") }.accessibilityLabel("Open photos").disabled(store.busy)
                }
            }
            .sheet(isPresented: $showFolder) {
                FolderPicker { url in
                    showFolder = false
                    Task { await store.importFolder(url) }
                }
            }
            .sheet(isPresented: $showAlbums) { AlbumPicker().environmentObject(store) }
            .sheet(isPresented: $showHelp) { help }
            .sheet(isPresented: $showDeletion) { DeleteReviewView(snapshot: deletionSnapshot).environmentObject(store) }
            .alert("Foliow", isPresented: Binding(get: {
                store.message != nil && !showDeletion && !showFolder && !showAlbums
            }, set: { if !$0 { store.message = nil } })) {
                Button("OK") { store.message = nil }
            } message: { Text(store.message ?? "") }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { store.persist() }
                if phase == .active { store.refreshPhotosAccess() }
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("MAKE ROOM FOR THE GOOD ONES").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(Palette.muted)
            Text(store.filter == .keep ? "The ones worth keeping." : store.filter == .pass ? "A second look?" : "Find your keepers.")
                .font(.system(size: 33, design: .serif)).tracking(-1).minimumScaleFactor(0.75).lineLimit(1)
            Text(store.session?.title ?? "Your photos. Your instinct. One swipe at a time.")
                .font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func filterLabel(_ filter: ReviewFilter) -> String {
        switch filter {
        case .review: return "Review \(store.items.count - store.reviewedCount)"
        case .keep: return "Keepers \(store.keptCount)"
        case .pass: return "Passed \(store.passed.count)"
        }
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Palette.soft).frame(width: 145, height: 160).rotationEffect(.degrees(-12)).offset(x: -20, y: 3)
                RoundedRectangle(cornerRadius: 18).fill(.white).frame(width: 145, height: 160).rotationEffect(.degrees(7)).shadow(color: .black.opacity(0.05), radius: 15)
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 53, weight: .ultraLight)).foregroundStyle(Palette.green)
            }.frame(height: 185)
            Text("Good photos deserve\na second look.").font(.system(size: 29, design: .serif)).multilineTextAlignment(.center)
            Text("Keep the ones you love.\nDelete the ones you pass when you’re ready.").font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            VStack(spacing: 12) {
                Button { showFolder = true } label: { Label("Open a Files folder", systemImage: "folder").frame(maxWidth: .infinity).padding(.vertical, 7) }.buttonStyle(.borderedProminent)
                Button { showAlbums = true } label: { Label("Open Photos library", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity).padding(.vertical, 7) }.buttonStyle(.bordered)
            }
            Text("CR2 & other iOS-supported RAW formats · HEIC · JPG · PNG & more")
                .font(.system(size: 10)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Label("Everything stays in its original place.", systemImage: "lock").font(.caption2).foregroundStyle(Palette.muted)
        }
    }

    private var decisionBar: some View {
        HStack(spacing: 12) {
            Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 28, height: 42) }
                .disabled(!store.canUndo || store.busy).accessibilityLabel("Undo last decision")
            Button { store.decide(.pass) } label: {
                Label("Pass", systemImage: "xmark").frame(maxWidth: .infinity).padding(.vertical, 9)
            }.buttonStyle(.bordered).tint(Palette.pass).disabled(store.previewLoading || store.busy)
            Button { store.decide(.keep) } label: {
                Label("Keep", systemImage: "heart").frame(maxWidth: .infinity).padding(.vertical, 9)
            }.buttonStyle(.borderedProminent).disabled(store.previewLoading || store.busy)
            Button { store.skip() } label: { Image(systemName: "arrow.right").frame(width: 28, height: 42) }
                .disabled(store.visible.count < 2 || store.busy).accessibilityLabel("Skip for now")
        }.font(.subheadline)
    }

    private var completed: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: store.filter == .review ? "checkmark.circle" : "photo.stack").font(.system(size: 52, weight: .ultraLight)).foregroundStyle(Palette.green)
            Text(store.filter == .review ? "That’s a wrap." : "Nothing here yet.").font(.system(size: 32, design: .serif))
            Text(store.filter == .review ? "\(store.keptCount) kept. \(store.passed.count) passed.\nKeepers stay exactly where they are." : "Your photos will appear here as you review.")
                .font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            if store.canUndo { Button("Undo last decision") { store.undo() } }
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private var progress: some View {
        VStack(spacing: 7) {
            ProgressView(value: Double(store.reviewedCount), total: Double(max(1, store.items.count))).tint(Palette.green)
            HStack {
                Text("\(store.reviewedCount) of \(store.items.count) reviewed")
                Spacer()
                Label("No uploads", systemImage: "lock")
            }.font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }

    private var help: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Less sorting.\nMore keepers.").font(.system(size: 36, design: .serif))
                    Label("Swipe right to keep. Left to pass.", systemImage: "hand.draw")
                    Label("Undo any decision before deleting.", systemImage: "arrow.uturn.backward")
                    Label("Review Passed, then confirm deletion.", systemImage: "trash")
                    Text("Keep leaves the original untouched. Pass only marks it; the app does not delete anything until you review the list and confirm.")
                    Text("Photos library deletions affect your library and synced iCloud Photos devices. Apple asks for permission and normally keeps deleted photos in Recently Deleted for 30 days.")
                    Text("Files deletions remove the actual originals from the selected folder, including subfolders. Recovery depends on the file provider and is not guaranteed. Files changed since review are skipped. RAW+JPEG files are reviewed separately in Files; a Photos RAW+JPEG or Live Photo is one library asset and deleting it removes that whole asset.")
                    Text("CR2 and other RAW previews use iOS’s image and Quick Look decoders. Support depends on the camera and iOS version. Unreadable previews remain available to skip or pass. Download cloud folders locally before using them. Photos may download previews from your iCloud library.")
                    Text("Decisions are saved on this iPhone. The latest folder or album session resumes when you reopen the app. No account, analytics or photo uploads.")
                }.font(.subheadline).padding(24)
            }.background(Palette.background)
                .navigationTitle("How it works").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showHelp = false } } }
        }
    }
}

struct ReviewCard: View {
    @EnvironmentObject private var store: ReviewStore
    let item: PhotoItem
    @State private var image: UIImage?
    @State private var error: String?
    @State private var loading = true
    @State private var offset: CGFloat = 0
    @State private var zoomed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    Palette.soft.opacity(0.6)
                    if loading { ProgressView("Opening your photo…").font(.caption) }
                    else if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .scaleEffect(zoomed ? 2 : 1)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .accessibilityLabel(item.name)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.badge.exclamationmark").font(.largeTitle)
                            Text("Preview unavailable").font(.headline)
                            Text(error ?? "This photo could not be opened.").font(.caption).multilineTextAlignment(.center)
                            Button("Retry") { Task { await load() } }
                        }.padding(25).foregroundStyle(Palette.muted)
                    }
                    if abs(offset) > 25 {
                        Text(offset > 0 ? "KEEP" : "PASS").font(.system(size: 32, weight: .bold, design: .rounded))
                            .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(offset > 0 ? Palette.green : Palette.pass)
                            .rotationEffect(.degrees(offset > 0 ? -12 : 12))
                    }
                }
                .clipped()
                .offset(x: offset)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(offset / 25)))
                .gesture(DragGesture(minimumDistance: 15).onChanged { value in
                    guard !zoomed, !loading, !store.busy, abs(value.translation.width) > abs(value.translation.height) else { return }
                    offset = value.translation.width
                }.onEnded { value in
                    guard !zoomed, !loading, !store.busy else { offset = 0; return }
                    let horizontal = abs(value.translation.width) > abs(value.translation.height)
                    if horizontal, abs(offset) > min(95, geometry.size.width * 0.22) { store.decide(offset > 0 ? .keep : .pass) }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { offset = 0 }
                })
                .onTapGesture(count: 2) { zoomed.toggle() }
                .overlay(alignment: .topTrailing) {
                    if image != nil {
                        Button { zoomed.toggle() } label: { Image(systemName: zoomed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").padding(10).background(.regularMaterial, in: Circle()) }
                            .padding(10).accessibilityLabel(zoomed ? "Fit photo" : "Zoom photo")
                    }
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.caption.weight(.medium)).lineLimit(1)
                    Text(item.origin == .files ? item.relativePath ?? "Files folder" : "Photos library")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer()
                if let fingerprint = item.fingerprint { Text(ByteCountFormatter.string(fromByteCount: fingerprint.bytes, countStyle: .file)).font(.caption2).foregroundStyle(Palette.muted) }
            }.padding(13).background(.white)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 17))
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .task(id: item.id) { await load() }
    }

    @MainActor private func load() async {
        loading = true; image = nil; error = nil; offset = 0; zoomed = false
        do {
            let preview = try await store.image(for: item)
            guard !Task.isCancelled else { return }
            image = preview
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
        loading = false
    }
}
