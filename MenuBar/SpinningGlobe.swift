import AppKit
import QuartzCore

/// The live menu-bar globe. A `CALayer` sublayer of the status button spins about its vertical axis
/// at a rate driven by live throughput, tinted by the connectivity tier. Spinning *in place* never
/// changes the item's width, so neighbouring menu-bar items never shift.
///
/// Good citizen: honours Reduce Motion (static globe), pauses on display sleep, and the display link
/// is paused whenever the globe is still — no idle render loop.
@MainActor
final class SpinningGlobe {
    let layer = CALayer()

    private weak var host: NSStatusBarButton?
    private var link: CADisplayLink?
    private var appearanceObservation: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []

    // Animation state.
    private var angle: CGFloat = 0          // current rotation (radians)
    private var omega: CGFloat = 0          // current angular velocity (radians/sec)
    private var targetOmega: CGFloat = 0    // eased toward this each frame
    private var lastT: CFTimeInterval = 0

    // Inputs, cached so environment changes (Reduce Motion / sleep) can re-decide.
    private var tier: StatusTier = .neutral
    private var wantSpin = false
    private var bytesPerSec: Double = 0

    // Environment.
    private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var asleep = false

    // Tuning.
    private let idleRevsPerSec = 0.15       // gentle drift when connected but idle (~1 rev / 6.7s)
    private let maxRevsPerSec = 1.8         // cap so a fast transfer never blurs (~1 rev / 0.55s)
    private let rampScale = 150_000.0       // bytes/sec where the ramp kicks in

    func attach(to button: NSStatusBarButton) {
        host = button
        button.wantsLayer = true
        layer.contentsGravity = .resizeAspect
        layer.zPosition = 1
        button.layer?.addSublayer(layer)
        relayout()
        rebuildImage()
        observeEnvironment()
    }

    /// Position a centred square and keep the bitmap crisp on the current screen.
    func relayout() {
        guard let host else { return }
        let b = host.bounds
        let side = max(2, min(b.height, b.width) - 3)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        layer.position = CGPoint(x: b.midX, y: b.midY)
        layer.contentsScale = host.window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }

    func setHidden(_ hidden: Bool) {
        layer.isHidden = hidden
        if hidden { stopLink() }
        applySpinDecision()
    }

    /// Feed the latest state. `colorize == false` forces the neutral (template) tint.
    func update(tier newTier: StatusTier, colorize: Bool, spin: Bool, bytesPerSec bytes: Double) {
        let resolvedTier = colorize ? newTier : .neutral
        if resolvedTier != tier { tier = resolvedTier; rebuildImage() }
        wantSpin = spin
        bytesPerSec = bytes
        applySpinDecision()
    }

    // MARK: - Spin lifecycle

    private func applySpinDecision() {
        let effective = wantSpin && !reduceMotion && !asleep && !layer.isHidden
        targetOmega = effective ? omega(forBytes: bytesPerSec) : 0
        if effective {
            startLink()
        }
        // When effective == false we let the link keep running until omega eases to ~0, then
        // step() snaps the globe upright and pauses the link.
    }

    private func omega(forBytes bytes: Double) -> CGFloat {
        let revs = idleRevsPerSec + 0.5 * log10(1 + max(0, bytes) / rampScale)
        let clamped = min(max(revs, idleRevsPerSec), maxRevsPerSec)
        return CGFloat(clamped * 2 * Double.pi)
    }

    private func ensureLink() {
        guard link == nil, let host else { return }
        let l = host.displayLink(target: self, selector: #selector(step(_:)))
        l.add(to: .current, forMode: .common)
        l.isPaused = true
        link = l
    }

    private func startLink() {
        ensureLink()
        link?.isPaused = false
    }

    private func stopLink() {
        link?.isPaused = true
        lastT = 0
    }

    @objc private func step(_ l: CADisplayLink) {
        let now = l.timestamp
        if lastT == 0 { lastT = now; return }
        let dt = now - lastT
        lastT = now

        // Frame-rate-independent easing of omega toward its target.
        let ease = CGFloat(1 - pow(0.0005, dt))
        omega += (targetOmega - omega) * ease
        angle += omega * CGFloat(dt)
        if angle >= .pi * 2 { angle -= .pi * 2 }
        applyTransform()

        // Once we've coasted to a near-stop and nothing wants us spinning, face front and idle.
        if targetOmega == 0 && abs(omega) < 0.02 {
            omega = 0
            angle = 0
            applyTransform()
            stopLink()
        }
    }

    private func applyTransform() {
        // Flat in-plane spin (about Z), like a wheel — matches the widget mockup the user approved.
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        CATransaction.commit()
    }

    // MARK: - Image

    private func rebuildImage() {
        let side = layer.bounds.width
        guard side > 1 else { return }
        let cfg = NSImage.SymbolConfiguration(pointSize: side * 0.92, weight: .semibold)
        guard let glyph = NSImage(systemSymbolName: "globe", accessibilityDescription: "Internet reachability")?
            .withSymbolConfiguration(cfg) else { return }
        glyph.isTemplate = true

        let appearance = host?.effectiveAppearance ?? NSApp.effectiveAppearance
        let image = NSImage(size: NSSize(width: side, height: side))
        appearance.performAsCurrentDrawingAppearance {
            image.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            let r = NSRect(x: (side - glyph.size.width) / 2,
                           y: (side - glyph.size.height) / 2,
                           width: glyph.size.width, height: glyph.size.height)
            glyph.draw(in: r)
            tintColor().set()
            NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
            image.unlockFocus()
        }
        layer.contents = image.layerContents(forContentsScale: layer.contentsScale)
    }

    private func tintColor() -> NSColor {
        switch tier {
        case .good: return .systemGreen
        case .warn: return .systemOrange
        case .bad: return .systemRed
        case .neutral: return .labelColor   // resolves to white/black against the menu bar
        }
    }

    // MARK: - Environment observation

    private func observeEnvironment() {
        let wc = NSWorkspace.shared.notificationCenter
        observers.append(wc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setAsleep(true) }
        })
        observers.append(wc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setAsleep(false) }
        })
        observers.append(wc.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshReduceMotion() }
        })
        // Menu-bar light/dark flip → re-tint the neutral globe so it stays visible.
        appearanceObservation = host?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.rebuildImage() }
        }
    }

    private func setAsleep(_ value: Bool) {
        asleep = value
        applySpinDecision()
    }

    private func refreshReduceMotion() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion { applyTransform() }   // settle upright immediately
        applySpinDecision()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for token in observers { center.removeObserver(token) }
    }
}
