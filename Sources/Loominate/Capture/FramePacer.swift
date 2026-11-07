import Dispatch

/// Fixed-rate tick on the capture queue; drives compositing and the heartbeat.
final class FramePacer {
    private let timer: DispatchSourceTimer

    init(queue: DispatchQueue, fps: Int, tick: @escaping () -> Void) {
        timer = DispatchSource.makeTimerSource(queue: queue)
        let interval = DispatchTimeInterval.nanoseconds(Int(1_000_000_000 / max(fps, 1)))
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(2))
        timer.setEventHandler(handler: tick)
    }

    func start() { timer.resume() }

    func stop() { timer.cancel() }
}
