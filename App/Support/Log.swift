import Foundation
import OSLog

enum Log {
    static let subsystem = "com.metaneutrons.kioskalator"

    static let configuration = Logger(subsystem: subsystem, category: "configuration")
    static let navigation = Logger(subsystem: subsystem, category: "navigation")
    static let kiosk = Logger(subsystem: subsystem, category: "kiosk")
    static let unlock = Logger(subsystem: subsystem, category: "unlock")
}
