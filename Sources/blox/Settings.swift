import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en_US")
        case .simplifiedChinese: Locale(identifier: "zh_CN")
        }
    }
}

struct Strings {
    let language: AppLanguage

    private func t(_ english: String, _ chinese: String) -> String {
        language == .english ? english : chinese
    }

    var stickyChip: String { t("Sticky note", "标签贴") }
    var listChip: String { t("Checklist", "列表事件") }
    var reminderChip: String { t("Reminder", "提醒事件") }
    var emptyCanvas: String { t("Drop your first note on the canvas", "在桌布上贴第一张贴纸") }
    var resizeHelp: String { t("Drag to resize the window", "拖拽调整窗口大小") }
    var listTitle: String { t("Title", "标题") }
    var newItem: String { t("New item", "新事项") }
    var emptyItem: String { t("(empty)", "（空）") }
    var delete: String { t("Delete", "删除") }
    var reminderPrefix: String { t("Reminder", "提醒") }
    var due: String { t("Time's up", "时间到") }
    var done: String { t("Done", "已完成") }
    var markDone: String { t("Mark as done", "标为完成") }
    var generalTab: String { t("General", "通用") }
    var aboutTab: String { t("About", "关于") }
    var aboutTagline: String { t("A lightweight menu-bar canvas for sticky notes, checklists, and reminders.", "轻量的菜单栏画布：标签贴、清单与提醒。") }
    var versionLabel: String { t("Version", "版本") }
    var settingsMenu: String { t("Settings…", "设置…") }
    var settingsTitle: String { t("Settings", "设置") }
    var quitApp: String { t("Quit Blox", "退出 Blox") }
    var languageLabel: String { t("Interface language", "界面语言") }
    var hotkeyLabel: String { t("Hotkey", "热键") }
    var comingSoon: String { t("Coming soon", "即将推出") }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey) }
    }

    private static let languageKey = "interfaceLanguage"

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.languageKey)
        language = AppLanguage(rawValue: saved ?? "") ?? .english
    }

    var strings: Strings { Strings(language: language) }
}
