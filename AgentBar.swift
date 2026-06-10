import AppKit
import Carbon
import Foundation
import UserNotifications

private let agentWatchPath = NSHomeDirectory() + "/.local/bin/agent-watch"
private let finishedSoundName = "Blow"
private let pollInterval: TimeInterval = 3.0
private let hotKeySignature = OSType(0x41474252)
private let hotKeyIdentifier = UInt32(1)
private let statusIconSize = NSSize(width: 26, height: 18)
private let statusAnimationInterval: TimeInterval = 1.0 / 18.0
private let sessionIconSize = NSSize(width: 18, height: 18)

private func appLog(_ message: String) {
    let line = "\(Date()) \(message)\n"
    if let data = line.data(using: .utf8) {
        FileHandle.standardOutput.write(data)
    }
}

private func agentEnvironment() -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    environment["HOME"] = NSHomeDirectory()
    return environment
}



private func statusIcon(total: Int, idle: Int, phase: TimeInterval) -> NSImage {
    let image = NSImage(size: statusIconSize)
    image.lockFocus()
    defer { image.unlockFocus() }

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: statusIconSize).fill()

    let center = NSPoint(x: 13, y: 9)
    let radius: CGFloat = 6.6
    let shownCount = idle > 0 ? idle : total
    let isActive = total > 0 && idle == 0
    let color: NSColor = isActive ? .systemGreen : (total > 0 ? .systemYellow : .tertiaryLabelColor)

    let circleRect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    if isActive {
        color.withAlphaComponent(0.16).setFill()
        NSBezierPath(ovalIn: circleRect.insetBy(dx: 1.5, dy: 1.5)).fill()

        color.withAlphaComponent(0.22).setStroke()
        let ring = NSBezierPath(ovalIn: circleRect)
        ring.lineWidth = 2.0
        ring.stroke()

        let arc = NSBezierPath()
        let startAngle = CGFloat((phase * 210.0).truncatingRemainder(dividingBy: 360.0))
        arc.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: startAngle + 230, clockwise: false)
        arc.lineWidth = 2.5
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    } else {
        color.setFill()
        NSBezierPath(ovalIn: circleRect).fill()
    }

    if shownCount > 0 {
        let label = shownCount > 9 ? "9+" : String(shownCount)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: label.count > 1 ? 6.5 : 8.0, weight: .bold),
            .foregroundColor: isActive ? NSColor.white : NSColor.black,
            .paragraphStyle: paragraph,
        ]
        let labelSize = label.size(withAttributes: attributes)
        let labelRect = NSRect(x: center.x - labelSize.width / 2, y: center.y - labelSize.height / 2, width: labelSize.width, height: labelSize.height)
        label.draw(in: labelRect, withAttributes: attributes)
    }

    image.isTemplate = false
    return image
}


private func sessionIcon(isIdle: Bool, phase: TimeInterval) -> NSImage {
    let image = NSImage(size: sessionIconSize)
    image.lockFocus()
    defer { image.unlockFocus() }

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: sessionIconSize).fill()

    let center = NSPoint(x: 9, y: 9)
    let radius: CGFloat = 6.4
    let color: NSColor = isIdle ? .systemYellow : .systemGreen
    let circleRect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

    if isIdle {
        color.setFill()
        NSBezierPath(ovalIn: circleRect).fill()
    } else {
        color.withAlphaComponent(0.16).setFill()
        NSBezierPath(ovalIn: circleRect.insetBy(dx: 1.5, dy: 1.5)).fill()

        color.withAlphaComponent(0.22).setStroke()
        let ring = NSBezierPath(ovalIn: circleRect)
        ring.lineWidth = 2.0
        ring.stroke()

        let arc = NSBezierPath()
        let startAngle = CGFloat((phase * 210.0).truncatingRemainder(dividingBy: 360.0))
        arc.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: startAngle + 230, clockwise: false)
        arc.lineWidth = 2.5
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }

    image.isTemplate = false
    return image
}

struct AgentSession: Codable {
    let id: String
    let tool: String
    let state: String
    let tty: String
    let cwd: String
    let label: String

    var isIdle: Bool { state == "idle" }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let workQueue = DispatchQueue(label: "com.max.agentbar.work", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var animationTimer: Timer?
    private var cached: [AgentSession] = []
    private var previousStates: [String: String] = [:]
    private var seeded = false
    private var lastCycledSessionID: String?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }

        menu.delegate = self
        statusItem.length = statusIconSize.width
        statusItem.menu = menu
        statusItem.button?.title = ""
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleNone
        updateStatusIcon()
        startStatusAnimation()
        registerHotKey()

        poll()
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    func applicationWillTerminate(_ notification: Notification) {
        animationTimer?.invalidate()
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if cached.isEmpty {
            let item = NSMenuItem(title: "No agent sessions", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            let phase = Date().timeIntervalSinceReferenceDate
            for session in cached {
                let item = NSMenuItem(title: session.label, action: #selector(focusMenuItem(_:)), keyEquivalent: "")
                item.image = sessionIcon(isIdle: session.isIdle, phase: phase)
                item.target = self
                item.representedObject = session.tty
                item.isEnabled = !session.tty.isEmpty
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let cycle = NSMenuItem(title: "Cycle Next Session", action: #selector(cycleNextSession), keyEquivalent: "a")
        cycle.target = self
        cycle.keyEquivalentModifierMask = [.control, .option, .command]
        cycle.isEnabled = cached.contains { !$0.tty.isEmpty }
        menu.addItem(cycle)
        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func refreshNow() {
        workQueue.async { [weak self] in self?.poll() }
    }

    @objc private func focusMenuItem(_ sender: NSMenuItem) {
        guard let tty = sender.representedObject as? String, !tty.isEmpty else { return }
        focus(tty)
    }

    @objc private func cycleNextSession() {
        let focusable = cached.filter { !$0.tty.isEmpty }
        guard !focusable.isEmpty else {
            lastCycledSessionID = nil
            return
        }

        let idleSessions = focusable.filter(\.isIdle)
        let eligible = idleSessions.isEmpty ? focusable : idleSessions
        let nextSession: AgentSession
        if let lastCycledSessionID, let index = eligible.firstIndex(where: { $0.id == lastCycledSessionID }) {
            nextSession = eligible[(index + 1) % eligible.count]
        } else {
            nextSession = eligible[0]
        }

        lastCycledSessionID = nextSession.id
        focus(nextSession.tty)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var eventHotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &eventHotKeyID
                )
                if status == noErr, eventHotKeyID.signature == hotKeySignature, eventHotKeyID.id == hotKeyIdentifier {
                    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                    DispatchQueue.main.async {
                        delegate.cycleNextSession()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandlerRef
        )
        if handlerStatus != noErr {
            appLog("hotkey_handler_error \(handlerStatus)")
            return
        }

        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: hotKeyIdentifier)
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        let registerStatus = RegisterEventHotKey(UInt32(kVK_ANSI_A), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if registerStatus != noErr {
            appLog("hotkey_register_error \(registerStatus)")
        }
    }

    private func poll() {
        let sessions = loadSessions()
        DispatchQueue.main.async { [weak self] in
            self?.apply(sessions)
        }
    }

    private func loadSessions() -> [AgentSession] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: agentWatchPath)
        process.arguments = ["json"]
        process.environment = agentEnvironment()

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")

        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            if process.terminationStatus != 0 {
                appLog("agent_watch_exit \(process.terminationStatus)")
                return []
            }
            do {
                return try JSONDecoder().decode([AgentSession].self, from: data)
            } catch {
                let text = String(data: data, encoding: .utf8) ?? ""
                appLog("decode_error \(error.localizedDescription) output=\(text.prefix(200))")
                return []
            }
        } catch {
            appLog("agent_watch_run_error \(error.localizedDescription) path=\(agentWatchPath) home=\(NSHomeDirectory())")
            return []
        }
    }

    private func apply(_ sessions: [AgentSession]) {
        let sorted = sessions.sorted { left, right in
            if left.isIdle != right.isIdle { return left.isIdle && !right.isIdle }
            return left.label.localizedCaseInsensitiveCompare(right.label) == .orderedAscending
        }
        let currentStates = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0.state) })

        cached = sorted
        if let lastCycledSessionID, !sorted.contains(where: { $0.id == lastCycledSessionID }) {
            self.lastCycledSessionID = nil
        }
        updateStatusIcon()

        if seeded {
            for session in sorted where previousStates[session.id] == "working" && session.state == "idle" {
                alert(session)
            }
        }

        previousStates = currentStates
        seeded = true
    }

    private func startStatusAnimation() {
        let timer = Timer(timeInterval: statusAnimationInterval, repeats: true) { [weak self] _ in
            self?.updateStatusIcon()
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func updateStatusIcon() {
        let idleCount = cached.filter(\.isIdle).count
        let phase = Date().timeIntervalSinceReferenceDate
        statusItem.button?.title = ""
        statusItem.button?.image = statusIcon(total: cached.count, idle: idleCount, phase: phase)
        updateOpenMenuIcons(phase: phase)
        if cached.isEmpty {
            statusItem.button?.toolTip = "AgentBar: no sessions"
        } else if idleCount > 0 {
            statusItem.button?.toolTip = "AgentBar: \(idleCount) waiting, \(cached.count) total"
        } else {
            statusItem.button?.toolTip = "AgentBar: \(cached.count) working"
        }
    }

    private func updateOpenMenuIcons(phase: TimeInterval) {
        for item in menu.items {
            guard let tty = item.representedObject as? String else { continue }
            guard let session = cached.first(where: { $0.tty == tty }) else { continue }
            item.image = sessionIcon(isIdle: session.isIdle, phase: phase)
        }
    }

    private func alert(_ session: AgentSession) {
        NSSound(named: NSSound.Name(finishedSoundName))?.play()

        let content = UNMutableNotificationContent()
        content.title = "Agent waiting on you"
        content.body = session.label
        content.userInfo = ["tty": session.tty]

        let request = UNNotificationRequest(identifier: "agentbar-\(session.id)-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                appLog("notify_error \(session.id) \(error.localizedDescription)")
            } else {
                appLog("notified \(session.id) \(session.tty)")
            }
        }
    }

    private func focus(_ tty: String) {
        workQueue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: agentWatchPath)
            process.arguments = ["focus", tty]
            process.environment = agentEnvironment()
            process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
            process.standardError = FileHandle(forWritingAtPath: "/dev/null")
            try? process.run()
            process.waitUntilExit()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let tty = response.notification.request.content.userInfo["tty"] as? String, !tty.isEmpty {
            focus(tty)
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
withExtendedLifetime(delegate) {
    app.run()
}
