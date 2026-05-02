import Foundation

@MainActor
protocol AudioRecorder: AnyObject {
    var startedAt: Date { get }
    var audioFiles: [AudioKind: URL] { get }
    func stop() async throws -> URL
}
