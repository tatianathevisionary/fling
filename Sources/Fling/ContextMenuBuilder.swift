import AppKit
import FlingKit

@MainActor
struct ContextMenuBuilder {
    let state: AppState

    func build() -> NSMenu {
        let menu = NSMenu()
        // Without this, AppKit ignores `isEnabled` and auto-enables everything.
        menu.autoenablesItems = false

        let casting = state.panel == .casting
        let castable = state.panel == .idleCastable || casting

        menu.addItem(action(casting ? "Cast this tab instead" : "Cast this tab",
                            key: "C", modifiers: [.command, .shift],
                            enabled: castable) { Task { await state.castCurrentTab() } })
        menu.addItem(action("Cast clipboard URL") { Task { await state.castClipboard() } })
        menu.addItem(.separator())

        if state.installedBrowsers.count > 1 {
            menu.addItem(submenu("Source", items: state.installedBrowsers.map { browser in
                action(browser.displayName) { Task { await state.select(browser: browser) } }
            }))
        }
        if !state.devices.isEmpty {
            menu.addItem(submenu("Device", items: state.devices.map { device in
                let item = action(device.name) { Task { await state.select(device: device) } }
                item.state = device == state.selectedDevice ? .on : .off
                return item
            }))
        }
        menu.addItem(.separator())

        menu.addItem(action(state.status.isPlaying ? "Pause" : "Play",
                            enabled: casting) { Task { await state.togglePlayPause() } })
        menu.addItem(action("Back \(AppState.seekStep)s", enabled: casting) {
            Task { await state.seek(by: -AppState.seekStep) }
        })
        menu.addItem(action("Forward \(AppState.seekStep)s", enabled: casting) {
            Task { await state.seek(by: AppState.seekStep) }
        })

        // NSMenu cannot host a slider, so offer presets instead.
        menu.addItem(submenu("Volume — \(state.volume)%",
                             items: stride(from: 0, through: 100, by: 10).map { level in
            let item = action("\(level)%") { state.setVolume(level) }
            item.state = abs(state.volume - level) < 5 ? .on : .off
            return item
        }))

        if state.selectedDevice != nil {
            menu.addItem(.separator())
            remoteItems().forEach { menu.addItem($0) }
        }

        menu.addItem(.separator())
        menu.addItem(action("Stop casting", key: ".", modifiers: [.command],
                            enabled: casting) { Task { await state.stopCasting() } })
        menu.addItem(.separator())

        let login = action("Open at Login") { LoginItem.toggle() }
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(action(Lang.switchTitle) { Lang.toggle() })
        menu.addItem(action("Quit Fling", key: "q", modifiers: [.command]) {
            NSApp.terminate(nil)
        })
        return menu
    }

    /// Scenes and the sleep timer, so neither needs the panel opened at night.
    private func remoteItems() -> [NSMenuItem] {
        let extras = state.remoteExtras
        var scenes = extras.scenes.map { scene in verbatim(scene.name) { extras.run(scene) } }
        if scenes.isEmpty { scenes.append(action("No scenes yet", enabled: false) {}) }
        if let running = extras.runningScene {
            scenes.append(.separator())
            scenes.append(action(tr("Stop the scene: ") + running) { extras.stopScene() })
        }
        scenes.append(.separator())
        scenes.append(action("New scene…") { SceneEditorWindow.open(extras, scene: nil) })
        if !extras.scenes.isEmpty {
            scenes.append(submenu("Edit", items: extras.scenes.map { scene in
                verbatim(scene.name) { SceneEditorWindow.open(extras, scene: scene) }
            }))
        }

        var timer = SleepTimer.choices.map { m in action("\(m) min") { extras.setSleep(minutes: m) } }
        if extras.sleepDeadline != nil {
            timer.append(.separator())
            timer.append(action("Cancel the timer") { extras.setSleep(minutes: nil) })
        }
        var timerTitle = tr("Sleep timer")
        if let left = extras.sleepMinutesLeft { timerTitle += " — " + tr("\(left) min") }
        return [submenu("Scenes", items: scenes), submenu(timerTitle, items: timer)]
    }

    // MARK: - helpers

    private func action(_ title: String,
                        key: String = "",
                        modifiers: NSEvent.ModifierFlags = [],
                        enabled: Bool = true,
                        handler: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: tr(title), action: #selector(Trampoline.fire), keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.isEnabled = enabled
        let trampoline = Trampoline(handler)
        item.target = trampoline
        item.representedObject = trampoline   // keeps the trampoline alive
        return item
    }

    /// A user-named item (a scene): its title is never translated.
    private func verbatim(_ title: String, handler: @escaping () -> Void) -> NSMenuItem {
        let item = action(title, handler: handler)
        item.title = title
        return item
    }

    private func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: tr(title), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        items.forEach { sub.addItem($0) }
        parent.submenu = sub
        return parent
    }
}

/// `NSMenuItem` needs an ObjC target; this carries a Swift closure to one.
final class Trampoline: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire() { handler() }
}
