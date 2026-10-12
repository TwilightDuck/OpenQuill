private actor HeldDecode {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async {
        await withCheckedContinuation { continuation in
            if released { continuation.resume() }
            else { self.continuation = continuation }
        }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

extension AppState {
    func verifyImmediateCancellation() async -> Bool {
        let gate = HeldDecode()
        phase = .processing
        run = Task { await gate.wait() }
        let pending = run!
        await Task.yield()
        let started = ContinuousClock.now
        cancel()
        let elapsed = started.duration(to: .now)
        let ready = phase == .idle && elapsed < .milliseconds(100)
        print("Cancel returned in \(elapsed); UI phase: \(phase.title)")
        await gate.release()
        await pending.value
        return ready
    }
}

@main private struct CancellationCheck {
    @MainActor static func main() async {
        _ = NSApplication.shared
        let state = AppState()
        let passed = await state.verifyImmediateCancellation()
        print(passed ? "PASS: cancellation returns to Ready without waiting for stalled decoding" : "FAIL: cancellation keeps the app busy waiting for decoding")
        exit(passed ? 0 : 1)
    }
}
