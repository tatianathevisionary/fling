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
        // remote pages
        "Arrows": "Стрелки", "Touchpad": "Тачпад", "Numbers": "Цифры", "Media": "Медиа",
        "Remote: arrows, touchpad, number keys or media keys": "Пульт: стрелки, тачпад, цифры или медиаклавиши",
        "Drag on the pad for arrows\nClick for OK, right-click for Back":
            "Ведите по панели — стрелки\nЩелчок — OK, правая кнопка — Назад",
        "Touchpad: drag for arrows, click for OK, right-click for Back, middle-click for Home":
            "Тачпад: ведите — стрелки, щелчок — OK, правая кнопка — Назад, средняя — Домой",
        "Channel +": "Канал +", "Channel −": "Канал −", "CH": "CH",
        "Input": "Источник", "Input source (HDMI, antenna…)": "Источник сигнала (HDMI, антенна…)",
        "Guide": "Телегид", "TV guide": "Телепрограмма",
        "Info": "Инфо", "Programme info": "Сведения о передаче",
        "Settings": "Настройки", "TV settings": "Настройки ТВ",
        "Previous track": "Предыдущий трек", "Next track": "Следующий трек",
        "Rewind": "Перемотка назад", "Fast-forward": "Перемотка вперёд",
        "Play / Pause": "Пауза / Играть", "Stop": "Стоп",
        "Subtitles": "Субтитры", "Audio track": "Звуковая дорожка",
        "Red button": "Красная кнопка", "Green button": "Зелёная кнопка",
        "Yellow button": "Жёлтая кнопка", "Blue button": "Синяя кнопка",
        "Colour buttons — for TV channels and teletext": "Цветные кнопки — для телеканалов и телетекста",
        // favourite apps
        "Click to open on the TV, right-click to edit": "Щелчок — открыть на ТВ, правая кнопка — изменить",
        "Move left": "Сдвинуть влево", "Move right": "Сдвинуть вправо",
        "Rename…": "Переименовать…", "Remove": "Убрать",
        "Add an app": "Добавить приложение",
        "Open on the TV: ": "Открытое на ТВ: ",
        "Enter a package…": "Указать пакет…",
        "Restore the default set": "Вернуть стандартный набор",
        "No more room — remove an app first.": "Мест больше нет — уберите какое-нибудь приложение.",
        "App package, e.g. org.videolan.vlc": "Пакет приложения, например org.videolan.vlc",
        "Button label": "Название на кнопке",
        "Add": "Добавить", "Save": "Сохранить",
        "That doesn't look like an Android package name.": "Это не похоже на имя пакета Android.",
        "Apps open once Fling is paired with the TV.": "Открыть приложение можно, когда Fling связан с ТВ.",
        // more menu, power, sleep timer
        "More: scenes, sleep timer, power": "Ещё: сцены, таймер сна, включение",
        "Turn on the TV": "Включить ТВ", "Turn off the TV": "Выключить ТВ",
        "Sleep timer": "Таймер сна", "Cancel the timer": "Отменить таймер",
        "The TV turns off in ": "ТВ выключится через ",
        "Sleep timer cancelled: another TV was selected.": "Таймер сна отменён: выбран другой ТВ.",
        "Can't turn the TV off: Fling isn't paired with it.": "Не могу выключить ТВ: Fling не связан с ним.",
        // scenes
        "Scenes": "Сцены", "No scenes yet": "Сцен пока нет", "New scene…": "Новая сцена…", "Edit": "Изменить",
        "Stop the scene: ": "Остановить сцену: ",
        "Movie night": "Вечер кино", "Fling — scene": "Fling — сцена", "Scene": "Сцена",
        "A scene runs its steps in order: for example, it turns on the TV, opens an app and sets the volume. Run it from the “⋯” menu in the panel or from the menu-bar icon's right-click menu.":
            "Сцена выполняет шаги по порядку: например, включает ТВ, открывает приложение и ставит громкость. Запустить её можно из меню «⋯» на панели или из меню значка в строке меню (правый щелчок).",
        "Name": "Название", "Switch to this TV first: ": "Сначала переключиться на ТВ: ",
        "Add a step": "Добавить шаг", "Up": "Выше", "Down": "Ниже", "Delete step": "Удалить шаг",
        "Delete scene": "Удалить сцену", "Run": "Запустить",
        "Delete the scene “": "Удалить сцену «", "”?": "»?",
        "Open an app": "Открыть приложение", "Remote button": "Кнопка пульта", "Wait": "Подождать",
        "Open: ": "Открыть: ", "TV volume: ": "Громкость ТВ: ", "Button: ": "Кнопка: ",
        "Wait: ": "Подождать: ", "Sleep timer: ": "Таймер сна: ",
        "Give the scene a name.": "Дайте сцене название.", "Add at least one step.": "Добавьте хотя бы один шаг.",
    
        "No app link known for this app — many TVs won't open it from here. Right-click to edit":
            "Ссылка для открытия этого приложения неизвестна — многие ТВ не откроют его отсюда. Правая кнопка — изменить",
        "Many TVs open only apps with their own app link (YouTube, Netflix…), not by package.":
            "Многие ТВ открывают только приложения со своей ссылкой (YouTube, Netflix…), а по имени пакета — нет.",
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
        (#"^(\d+) min$"#, "$1 мин"),
        (#"^(\d+) s$"#, "$1 с"),
        (#"^Scene “(.+)”: the TV doesn't report its volume — step skipped\.$"#,
         "Сцена «$1»: ТВ не сообщает громкость — шаг пропущен."),
        (#"^TV “(.+)” not found — the scene ran on the current TV\.$"#,
         "ТВ «$1» не найден — сцена выполнена на текущем ТВ."),
        (#"^The TV didn't open (.+): Fling knows no app link for it, and most TVs won't open an app by its package name\. Open it from the TV's home screen\.$"#,
         "ТВ не открыл $1: ссылка для этого приложения неизвестна, а по имени пакета большинство ТВ приложения не открывают. Откройте его с главного экрана ТВ."),
        (#"^The TV didn't open (.+): this TV doesn't accept the app's link\. Open it from the TV's home screen\.$"#,
         "ТВ не открыл $1: этот ТВ не принимает ссылку приложения. Откройте его с главного экрана ТВ."),
    ].map { (try! NSRegularExpression(pattern: $0.0, options: [.dotMatchesLineSeparators]), $0.1) }

    /// Pieces the onboarding text builds its browser list from.
    static func fixList(_ s: String) -> String {
        s.replacingOccurrences(of: " and ", with: " и ")
         .replacingOccurrences(of: "your browser", with: "вашему браузеру")
    }
}
