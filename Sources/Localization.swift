import Foundation

enum L10n {
    static func string(_ key: String, defaultValue: String) -> String {
        NSLocalizedString(
            key,
            tableName: "Localizable",
            bundle: .main,
            value: defaultValue,
            comment: ""
        )
    }

    static func format(_ key: String, defaultValue: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key, defaultValue: defaultValue),
            locale: Locale.current,
            arguments: arguments
        )
    }
}
