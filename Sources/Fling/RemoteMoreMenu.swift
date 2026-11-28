import SwiftUI
import FlingKit

/// The "⋯" key in the remote header: scenes, the sleep timer, Turn on / Turn off.
/// ContextMenuBuilder offers the same scenes and timer in the menu-bar icon's
/// right-click menu.
struct RemoteMoreMenu: View {
    @ObservedObject var extras: RemoteExtras

    init(state: AppState) { extras = state.remoteExtras }

    var body: some View {
        Menu {
            Menu(tr("Scenes")) {
                ForEach(extras.scenes) { sc in
                    Button(sc.name) { extras.run(sc) }
                }
                if extras.scenes.isEmpty { Text(tr("No scenes yet")) }
                if let running = extras.runningScene {
                    Divider()
                    Button(tr("Stop the scene: ") + running) { extras.stopScene() }
                }
                Divider()
                Button(tr("New scene…")) { SceneEditorWindow.open(extras, scene: nil) }
                if !extras.scenes.isEmpty {
                    Menu(tr("Edit")) {
                        ForEach(extras.scenes) { sc in
                            Button(sc.name) { SceneEditorWindow.open(extras, scene: sc) }
                        }
                    }
                }
            }
            Menu(sleepTitle) {
                ForEach(SleepTimer.choices, id: \.self) { m in
                    Button(tr("\(m) min")) { extras.setSleep(minutes: m) }
                }
                if extras.sleepDeadline != nil {
                    Divider()
                    Button(tr("Cancel the timer")) { extras.setSleep(minutes: nil) }
                }
            }
            Divider()
            Button(tr("Turn on the TV")) { Task { await extras.turnOn() } }
            Button(tr("Turn off the TV")) { Task { await extras.turnOff() } }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 11, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // the borderless menu drops a label's background, so the circle sits behind it
        .frame(width: 26, height: 26)
        .background(Circle().fill(Color.primary.opacity(0.07)))
        .contentShape(Circle())
        .help(tr("More: scenes, sleep timer, power"))
    }

    private var sleepTitle: String {
        guard let left = extras.sleepMinutesLeft else { return tr("Sleep timer") }
        return tr("Sleep timer") + " — " + tr("\(left) min")
    }
}

/// "☾ Sleep timer: the TV turns off in 25 min   [Cancel]" under the remote header.
struct SleepTimerRow: View {
    @ObservedObject var extras: RemoteExtras

    init(state: AppState) { extras = state.remoteExtras }

    var body: some View {
        if let deadline = extras.sleepDeadline {
            TimelineView(.periodic(from: .now, by: 15)) { ctx in
                HStack(spacing: 6) {
                    Image(systemName: "moon.fill").font(.system(size: 10))
                    Text(tr("The TV turns off in ")
                         + tr("\(SleepTimer.minutesLeft(until: deadline, now: ctx.date)) min"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 4)
                    Button(tr("Cancel")) { extras.setSleep(minutes: nil) }
                        .help(tr("Cancel the timer"))
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 12).padding(.bottom, 6)
        }
    }
}
