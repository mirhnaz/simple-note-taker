import AppKit
import SwiftUI

@MainActor
@Observable
final class LibraryViewModel {
    private(set) var meetings: [MeetingFile] = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    var searchQuery: String = ""
    var selectedID: MeetingFile.ID?

    private let directoryProvider: @MainActor () -> URL

    init(directoryProvider: @escaping @MainActor () -> URL = { AppSettings.shared.notesDirectory }) {
        self.directoryProvider = directoryProvider
    }

    var filteredMeetings: [MeetingFile] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return meetings }
        return meetings.filter { meeting in
            if meeting.displayTitle.lowercased().contains(q) { return true }
            if let snippet = meeting.summarySnippet, snippet.lowercased().contains(q) { return true }
            return false
        }
    }

    var selectedMeeting: MeetingFile? {
        guard let selectedID else { return nil }
        return meetings.first(where: { $0.id == selectedID })
    }

    func refresh() async {
        let directory = directoryProvider()
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await MeetingLibrary.load(from: directory)
            self.meetings = loaded
            self.lastError = nil
            if let selectedID, !loaded.contains(where: { $0.id == selectedID }) {
                self.selectedID = loaded.first?.id
            } else if selectedID == nil {
                self.selectedID = loaded.first?.id
            }
        } catch {
            self.lastError = error.localizedDescription
        }
    }
}

struct LibraryWindow: View {
    @Bindable private var viewModel = LibraryViewModel()

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 260)
        } detail: {
            detail
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .task { await viewModel.refresh() }
        .onAppear { AppActivation.shared.windowDidAppear() }
        .onDisappear { AppActivation.shared.windowDidDisappear() }
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            if viewModel.meetings.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No meetings yet",
                    systemImage: "books.vertical",
                    description: Text("Start your first recording from the menu bar.")
                )
            } else {
                List(selection: $viewModel.selectedID) {
                    ForEach(viewModel.filteredMeetings) { meeting in
                        meetingRow(meeting)
                            .tag(meeting.id)
                    }
                }
                .listStyle(.sidebar)
                .searchable(text: $viewModel.searchQuery, placement: .sidebar, prompt: "Search meetings")
            }
            if let error = viewModel.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func meetingRow(_ meeting: MeetingFile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(meeting.displayTitle)
                .font(.headline)
                .lineLimit(2)
            Text(meeting.recordedAt, format: .dateTime.year().month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
            if let snippet = meeting.summarySnippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var detail: some View {
        if let meeting = viewModel.selectedMeeting {
            MeetingDetailView(meeting: meeting)
        } else {
            ContentUnavailableView("Select a meeting", systemImage: "doc.text")
        }
    }
}

private struct MeetingDetailView: View {
    let meeting: MeetingFile
    @State private var content: String = ""
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading) {
                    Text(meeting.displayTitle).font(.title2).bold()
                    Text(meeting.recordedAt, format: .dateTime.weekday().month().day().year().hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(meeting.url)
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([meeting.url])
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
            }
            .padding()
            Divider()
            ScrollView {
                if let loadError {
                    Text(loadError).foregroundStyle(.red).padding()
                } else {
                    Text(LocalizedStringKey(content))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
        .task(id: meeting.url) { await loadContent() }
    }

    private func loadContent() async {
        do {
            content = try String(contentsOf: meeting.url, encoding: .utf8)
            loadError = nil
        } catch {
            content = ""
            loadError = "Couldn't load: \(error.localizedDescription)"
        }
    }
}
