import AppKit
import SwiftUI
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

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Text(settings.strings.generalTab) }
            AboutSettingsView()
                .tabItem { Text(settings.strings.aboutTab) }
        }
        .frame(width: 420, height: 300)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let s = settings.strings
        Form {
            Picker(s.languageLabel, selection: $settings.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.radioGroup)
            HStack {
                Text(s.hotkeyLabel)
                Spacer()
                Text(s.comingSoon)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

struct AboutSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var body: some View {
        let s = settings.strings
        VStack(spacing: 10) {
            if let url = Bundle.module.url(forResource: "blox-logo", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 56, height: 56)
            }
            Text("Blox")
                .font(.system(size: 18, weight: .semibold))
            Text(s.aboutTagline)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Text("\(s.versionLabel) \(version)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Link("github.com/halfstring/blox", destination: URL(string: "https://github.com/halfstring/blox")!)
                .font(.system(size: 11))
            Text("MIT © 2026 halfstring")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private var window: NSWindow?
    private var cancellable: AnyCancellable?

    init(settings: AppSettings) {
        self.settings = settings
        cancellable = settings.$language.sink { [weak self] language in
            self?.window?.title = Strings(language: language).settingsTitle
        }
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = settings.strings.settingsTitle
            window.contentView = NSHostingView(rootView: SettingsView().environmentObject(settings))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
