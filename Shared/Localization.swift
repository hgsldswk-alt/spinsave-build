import Foundation

enum L {
    static func t(_ key: String) -> String { NSLocalizedString(key, comment: "") }
    static func f(_ key: String, _ values: String...) -> String {
        String(format: t(key), locale: Locale.current, arguments: values)
    }
    static func goalName(_ goal: Goal) -> String {
        goal.name.isEmpty ? t(goal.hasTarget ? "我的存钱目标" : "每天随手存点") : goal.name
    }
    static func achievement(_ id: String) -> String {
        if id.hasPrefix("streak-"), let n = Int(id.dropFirst(7)) { return f("连续存钱 %@ 天", String(n)) }
        if id.hasPrefix("total-"), let n = Int(id.dropFirst(6)) { return f("累计存下 %@", Money.yuan(n)) }
        return t("目标达成")
    }
}
