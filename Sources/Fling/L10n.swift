import AppKit

/// Russian / English, the same way as the Windows / Linux builds.
///
/// The code stays English: every user-visible string (Text, Button, Menu,
/// TextField, .help, menu items) goes through `tr()`, which swaps it for the
/// Russian phrase when the app runs in Russian. Strings with nothing in the table pass through unchanged.
///
/// Language: follows macOS by default; the "Language" row in the panel and the
/// right-click menu switches it and relaunches Fling (stored in UserDefaults).
enum Lang {
    private static let key = "lang"   // "ru" | "en"; absent = follow the system

    static let current: String = {
        if let saved = UserDefaults.standard.string(forKey: key), ["ru", "en"].contains(saved) {
            return saved
        }
        return (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("ru") ? "ru" : "en"
    }()

    static var isRussian: Bool { current == "ru" }

    /// Row title, like the Windows flag's tooltip: current → other.
    static var switchTitle: String {
        isRussian ? "🇷🇺  Язык: Русский → English" : "🇬🇧  Language: English → Русский"
    }

    static func toggle() {
        UserDefaults.standard.set(isRussian ? "en" : "ru", forKey: key)
        UserDefaults.standard.synchronize()
        // relaunch once this instance has quit
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.7; /usr/bin/open -n \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }
}

/// Pairing code: the keys under A–F on a Russian layout give ф и с в у а —
/// map them back, keep hex only, at most 6 (same as the Windows build).
func pinClean(_ s: String) -> String {
    let ru: [Character: Character] = ["ф": "A", "и": "B", "с": "C", "в": "D", "у": "E", "а": "F"]
    let mapped = s.lowercased().map { ru[$0] ?? Character($0.uppercased()) }
    return String(mapped.filter { "0123456789ABCDEF".contains($0) }.prefix(6))
}

func tr<S: StringProtocol>(_ s: S) -> String {
    let text = String(s)
    guard Lang.isRussian, !text.isEmpty else { return text }
    if let ru = RU.exact[text] { return ru }
    for (rx, template) in RU.patterns {
        let range = NSRange(text.startIndex..., in: text)
        if rx.firstMatch(in: text, range: range) != nil {
            return RU.fixList(rx.stringByReplacingMatches(in: text, range: range, withTemplate: template))
        }
    }
    return text
}

private enum RU {
    static let exact: [String: String] = [
        // panel
        "Fling needs permission": "Fling нужно разрешение",
        "Grant access": "Дать доступ",
        "Open Settings": "Открыть Настройки",
        "Fling needs catt": "Fling нужен catt",
        "The Cast engine isn't installed. Install it once and Fling will find it.":
            "Движок трансляции не установлен. Установите его один раз — Fling его найдёт.",
        "Copy install command": "Скопировать команду установки",
        "No page open": "Нет открытой страницы",
        "Not a video page": "Это не страница с видео",
        "Not a web page": "Это не веб-страница",
        "castable": "можно транслировать",
        "Casting…": "Отправляю…",
        "Cast this tab": "Отправить эту вкладку",
        "Cast this tab instead": "Отправить эту вкладку вместо",
        "Cast clipboard URL": "Отправить ссылку из буфера",
        "Open at Login": "Запускать при входе",
        "✓ Open at Login": "✓ Запускать при входе",
        "Quit Fling": "Выйти из Fling",
        "Playing": "Воспроизводится",
        "Pause": "Пауза",
        "Play": "Играть",
        "Stop casting": "Остановить трансляцию",
        "Chromecast plays media streams, not web pages. Try a video page.":
            "Chromecast показывает видео и звук, а не веб-страницы. Откройте страницу с видео.",
        "Open a tab in Chrome or Safari, then try again.":
            "Откройте вкладку в Chrome или Safari и попробуйте снова.",
        "Source": "Источник",
        "Device": "Устройство",
        "Enter the code on the TV screen": "Введите код с экрана телевизора",
        "Pair": "Связать",
        "Cancel": "Отмена",
        "No device found": "ТВ не найден",
        "Switch": "Сменить",
        // remote
        "Contacting TV…": "Связываюсь с ТВ…",
        "Keyboard captured — keys go to the TV. Esc releases it. Click to turn capture off":
            "Клавиатура управляет ТВ. Esc — вернуть клавиатуру. Нажмите, чтобы отключить захват",
        "Keyboard captured — ← → seek, Space pauses. Esc releases it. Click to turn capture off":
            "Клавиатура управляет трансляцией: ← → перемотка, пробел — пауза. Esc — вернуть клавиатуру. Нажмите, чтобы отключить захват",
        "Keyboard capture is off — click to control the TV from the Mac keyboard":
            "Захват клавиатуры выключен — нажмите, чтобы управлять ТВ с клавиатуры Mac",
        "off": "выкл",
        "Pair once with the TV to unlock apps, the d-pad, and typing.":
            "Один раз свяжите Fling с ТВ — откроются приложения, стрелки и ввод текста.",
        "Turn TV On": "Включить ТВ",
        "Set Up TV Power…": "Настроить питание ТВ…",
        "ON THE TV": "НА ТВ",
        "TV is off": "ТВ выключен",
        "Turn TV off": "Выключить ТВ",
        "Turn TV on": "Включить ТВ",
        "Toggle TV power": "Вкл/выкл ТВ",
        "Back": "Назад",
        "Home": "Домой",
        "or scroll anywhere to move around the TV": "или крутите колёсико / тачпад в любом месте панели",
        "WASD move · E ⏎ OK · Q ⌫ back · ± vol": "WASD ход · E ⏎ OK · Q ⌫ назад · ± громк.",
        "↑↓←→ move · ⏎ OK · ⌫ back · ± vol": "↑↓←→ ход · ⏎ OK · ⌫ назад · ± громк.",
        "space pause · ⇧A D seek · ⌘V paste · esc exit": "пробел пауза · ⇧A D перемотка · ⌘V вставить · esc выйти",
        "space pause · ⇧← → seek · ⌘V paste · esc exit": "пробел пауза · ⇧← → перемотка · ⌘V вставить · esc выйти",
        "Move with the arrow keys": "Управлять стрелками",
        "Move with W A S D (E = OK, Q = Back)": "Управлять W A S D (E = OK, Q = Назад)",
        "Arrow keys": "Стрелки",
        "arrow keys, or scroll anywhere, to move around the TV":
            "стрелки на клавиатуре или колёсико / тачпад — движение по ТВ",
        "Vol −": "Громк −",
        "Vol +": "Громк +",
        "Mute": "Без звука",
        "Hide keyboard": "Скрыть клавиатуру",
        "Show keyboard": "Показать клавиатуру",
        "Keyboard — type on the TV": "Клавиатура — печать на ТВ",
        "Type on TV": "Печать на ТВ",
        "Lands in whatever text field is focused on the TV": "Текст попадёт в поле, выбранное на ТВ",
        "Voice search": "Голосовой поиск",
        "Stop voice search": "Остановить голосовой поиск",
        "Listening — click the mic again when done.": "Слушаю — нажмите микрофон ещё раз, когда закончите.",
        "Keyboard — type on the TV (right-click for options)": "Клавиатура — печать на ТВ (правый клик — настройки)",
        "Live — letters appear as you type": "Сразу — буквы появляются на ТВ по мере ввода",
        "✓ Live — letters appear as you type": "✓ Сразу — буквы появляются на ТВ по мере ввода",
        "Send on Return": "Отправлять по Enter",
        "✓ Send on Return": "✓ Отправлять по Enter",
        "Paste clipboard on the TV": "Вставить из буфера на ТВ",
        "Paste clipboard on the TV  (⌘V)": "Вставить из буфера на ТВ  (⌘V)",
        "Type — shows on the TV live": "Печатайте — сразу на ТВ",
        "Type, Return sends": "Напишите и нажмите Enter",
        "Live typing is on — click to send on Return instead": "Печать сразу включена — нажмите, чтобы отправлять по Enter",
        "Live typing is off — click to turn on": "Печать сразу выключена — нажмите, чтобы включить",
        "TV volume": "Громкость телевизора",
        "TV sound: click to mute / unmute": "Звук ТВ: щёлкните, чтобы выключить / включить",
        // errors (FlingKit)
        "Clipboard is empty": "Буфер обмена пуст",
        "No device selected": "Устройство не выбрано",
        "catt is not installed": "catt не установлен",
        "That code doesn't match — read it off the TV again.": "Код не совпадает — посмотрите на экран ТВ ещё раз.",
        "The TV rejected the pairing code. Start over.": "ТВ отклонил код. Начните заново.",
        "The TV no longer trusts this Mac — run TV power setup again.":
            "ТВ больше не доверяет этому Mac — настройте питание ТВ заново.",
        "The TV closed the connection during the handshake.": "ТВ разорвал соединение при подключении.",
        "The TV didn't answer.": "ТВ не ответил.",
        "Run TV power setup first.": "Сначала настройте питание ТВ.",
        "This TV session declined voice — use typed search instead.":
            "ТВ не принял голос — наберите запрос текстом.",
        "The TV didn't open voice search.": "ТВ не открыл голосовой поиск.",
        "The TV did not respond. Make sure it is awake, then try again.":
            "ТВ не отвечает. Убедитесь, что он включён, и попробуйте снова.",
    ]

    static let patterns: [(NSRegularExpression, String)] = [
        (#"^Back (\d+)s$"#, "Назад $1 с"),
        (#"^Forward (\d+)s$"#, "Вперёд $1 с"),
        (#"^Volume — (\d+)%$"#, "Громкость — $1%"),
        (#"^Now: (.+)$"#, "Сейчас: $1"),
        (#"^Resume on TV at (.+)$"#, "Возобновить на ТВ с $1"),
        (#"^Couldn't reach the TV \((.*)\)\.$"#, "Не удалось связаться с ТВ ($1)."),
        (#"^Certificate problem \((.*)\)\.$"#, "Проблема с сертификатом ($1)."),
        (#"^Turn on (.+) ▸ Develop ▸ Allow JavaScript from Apple Events to resume videos where you left off\.$"#,
         "Включите в $1 ▸ Разработка ▸ «Разрешить JavaScript из событий Apple», чтобы видео продолжалось с того же места."),
        (#"^macOS asks separately for each app\. Fling needs (.+) so it can read the address of your frontmost tab\.$"#,
         "macOS спрашивает отдельно для каждого приложения. Fling нужен доступ к $1, чтобы читать адрес открытой вкладки."),
    ].map { (try! NSRegularExpression(pattern: $0.0, options: [.dotMatchesLineSeparators]), $0.1) }

    /// Pieces the onboarding text builds its browser list from.
    static func fixList(_ s: String) -> String {
        s.replacingOccurrences(of: " and ", with: " и ")
         .replacingOccurrences(of: "your browser", with: "вашему браузеру")
    }
}
