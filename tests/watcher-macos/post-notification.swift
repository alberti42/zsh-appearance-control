// Posts the notification macOS sends when the appearance changes, the given
// number of times (default 1). The value does not change: the watcher re-reads
// it, so this exercises the trigger, the debounce and the skip.
//
// usage: swift post-notification.swift [count]

import Foundation

let count = CommandLine.arguments.dropFirst().first.flatMap { Int($0) } ?? 1
for _ in 0..<count {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("AppleInterfaceThemeChangedNotification"),
        object: nil, userInfo: nil, deliverImmediately: true)
}
