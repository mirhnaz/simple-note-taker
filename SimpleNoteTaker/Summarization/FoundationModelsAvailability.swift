import FoundationModels
import Foundation

/// Centralised "is Apple's on-device model usable right now?" check, with a
/// user-facing message when it isn't. macOS doesn't expose a way to *trigger*
/// the Apple Intelligence model download — it's controlled from System
/// Settings → Apple Intelligence & Siri. The best we can do is detect the
/// state and explain what the user needs to do next.
enum FoundationModelsAvailability {
    /// Returns nil if the model is available and ready to use.
    /// Otherwise returns a short message suitable for display to the user.
    static func currentMessage() -> String? {
        let model = SystemLanguageModel.default
        guard !model.isAvailable else { return nil }
        let detail = String(describing: model.availability).lowercased()
        if detail.contains("appleintelligence") || detail.contains("notenabled") {
            return "Apple Intelligence is off. Enable it in System Settings → Apple Intelligence & Siri, then click Regenerate."
        }
        if detail.contains("notready") || detail.contains("downloading") || detail.contains("preparing") {
            return "Apple Intelligence is downloading its on-device model. Wait a few minutes for it to finish, then click Regenerate."
        }
        if detail.contains("noteligible") || detail.contains("unsupported") {
            return "This Mac doesn't support Apple Intelligence. Switch to Ollama in Settings to generate summaries."
        }
        return "Apple Intelligence is unavailable (\(detail)). Try Regenerate later, or switch to Ollama in Settings."
    }
}
