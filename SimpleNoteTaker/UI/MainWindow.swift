import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case recording
    case meetings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recording: return "Recording"
        case .meetings: return "Meetings"
        }
    }

    var systemImage: String {
        switch self {
        case .recording: return "mic.fill"
        case .meetings: return "calendar"
        }
    }
}

@MainActor
@Observable
final class MainViewModel {
    var selectedTab: MainTab = .recording
}

struct MainWindow: View {
    @Bindable private var viewModel = MainViewModel()
    @Bindable private var controller = RecordingController.shared
    @State private var showingSetupSheet = false

    var body: some View {
        VStack(spacing: 0) {
            setupBanner
            tabBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(Color.appWindowBackground)
        .onAppear { AppActivation.shared.windowDidAppear() }
        .onDisappear { AppActivation.shared.windowDidDisappear() }
        .sheet(
            isPresented: $showingSetupSheet,
            onDismiss: {
                Task { await controller.refreshSummarizerStatus() }
            }
        ) {
            SummarizerSetupSheet()
        }
    }

    @ViewBuilder
    private var setupBanner: some View {
        if let message = controller.summarizerStatus.unavailableMessage {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Summarization isn't ready").font(.callout).bold()
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Set up") { showingSetupSheet = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.orange.opacity(0.10))
            Divider()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(MainTab.allCases) { tab in
                tabButton(tab)
            }
            Spacer()
        }
    }

    private func tabButton(_ tab: MainTab) -> some View {
        let isSelected = viewModel.selectedTab == tab
        return Button {
            viewModel.selectedTab = tab
        } label: {
            Label(tab.label, systemImage: tab.systemImage)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.gray.opacity(0.18) : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.selectedTab {
        case .recording:
            RecordingTabView()
        case .meetings:
            MeetingsTabView()
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
