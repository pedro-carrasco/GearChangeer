import Foundation

enum L10n {
    private static var bundle: Bundle {
        if Bundle.main.path(forResource: "Localizable", ofType: "strings") != nil {
            return .main
        }
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }

    static func string(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: bundle, value: key, comment: "")
    }

    static func format(_ key: String, _ args: any CVarArg...) -> String {
        let formatString = string(key)
        return String(format: formatString, locale: Locale.current, arguments: args)
    }
}
