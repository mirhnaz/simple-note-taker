import AppKit
import SwiftUI

struct MeetingsTabView: View {
    @Environment(\.openWindow) private var openWindow

    @State private var meetings: [MeetingFile] = []
    @State private var searchQuery: String = ""
    @State private var isLoading = false
    @State private var lastError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .task { await refresh() }
    }

    private var filteredMeetings: [MeetingFile] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return meetings }
        return meetings.filter { meeting in
            if meeting.displayTitle.lowercased().contains(q) { return true }
            if let snippet = meeting.summarySnippet, snippet.lowercased().contains(q) { return true }
            return false
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Previous Meetings")
                .font(.title3.bold())
            Spacer()
            TextField("Search", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            .disabled(isLoading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && meetings.isEmpty {
            ProgressView().padding(60).frame(maxWidth: .infinity)
        } else if filteredMeetings.isEmpty {
            placeholder
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(filteredMeetings) { meeting in
                        meetingCard(meeting)
                    }
                }
                .padding(18)
            }
        }
        if let lastError {
            Text(lastError)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
        }
    }

    private func meetingCard(_ meeting: MeetingFile) -> some View {
        Button {
            openWindow(value: meeting.recordedAt)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.displayTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(meeting.recordedAt, format: .dateTime.weekday().month().day().hour().minute())
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
                Spacer()
                if let durationLabel = meeting.durationLabel {
                    Text(durationLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.appCardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.gray.opacity(0.18), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            if searchQuery.isEmpty {
                Text("No meetings yet").font(.title3).foregroundStyle(.secondary)
                Text("Switch to the Recording tab to start your first meeting.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No matches for \"\(searchQuery)\"")
                    .font(.title3).foregroundStyle(.secondary)
            }
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            meetings = try await MeetingLibrary.load(from: AppSettings.shared.notesDirectory)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
