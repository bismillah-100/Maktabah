//
//  NotificationName.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 01/05/26.
//

import Foundation

extension Notification.Name {
    // static let backgroundDidChange = Notification.Name("backgroundDidChange")
    static let didChangeClickableAnnotation = Notification.Name("didChangeClickableAnnotation")
    static let didChangeHarakat = Notification.Name("didChangeHarakat")
    static let didChangeBackground = Notification.Name("didChangeBackground")
    static let didChangeFont = Notification.Name("didChangeFont")
    static let didChangeLineHeight = Notification.Name("didChangeLineHeight")

    // MARK: - WINDOW OBSERVATIONS
    static let windowTabBarDidChange = Notification.Name("windowTabBarDidChange")
}
