//
//  AnnotationNode.swift
//  Maktabah
//

import Foundation

enum AnnotationNodeKind {
    case root
    case book
    case tag
    case untagged
    case dateBucket
    case annotation
}

enum DateBucket: Hashable, Comparable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case lastMonth
    case older(year: Int, month: Int)

    var localizedTitle: String {
        switch self {
        case .today:
            String(localized: .Annotation.today)
        case .yesterday:
            String(localized: .Annotation.yesterday)
        case .thisWeek:
            String(localized: .Annotation.thisWeek)
        case .thisMonth:
            String(localized: .Annotation.thisMonth)
        case .lastMonth:
            String(localized: .Annotation.lastMonth)
        case let .older(year, month):
            Self.formatOlder(year: year, month: month)
        }
    }

    private static func formatOlder(year: Int, month: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let date = Calendar.current.date(from: components) ?? Date()

        let currentYear = Calendar.current.component(.year, from: Date())
        let formatter = DateFormatter()
        if year == currentYear {
            formatter.dateFormat = "MMMM"
        } else {
            formatter.dateFormat = "MMMM yyyy"
        }
        return formatter.string(from: date)
    }

    static func bucket(
        for timestamp: Int64,
        relativeTo now: Date = Date(),
        calendar: Calendar = .current
    ) -> DateBucket {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))

        if calendar.isDateInToday(date) {
            return .today
        }
        if calendar.isDateInYesterday(date) {
            return .yesterday
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year),
           calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
        {
            return .thisWeek
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year),
           calendar.isDate(date, equalTo: now, toGranularity: .month)
        {
            return .thisMonth
        }

        if let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: now),
           calendar.isDate(date, equalTo: lastMonthDate, toGranularity: .year),
           calendar.isDate(date, equalTo: lastMonthDate, toGranularity: .month)
        {
            return .lastMonth
        }

        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return .older(year: year, month: month)
    }

    var chronologicalOrder: Int64 {
        switch self {
        case .today:
            Int64.max
        case .yesterday:
            Int64.max - 1
        case .thisWeek:
            Int64.max - 2
        case .thisMonth:
            Int64.max - 3
        case .lastMonth:
            Int64.max - 4
        case let .older(year, month):
            Int64(year * 100 + month)
        }
    }

    static func < (lhs: DateBucket, rhs: DateBucket) -> Bool {
        lhs.chronologicalOrder < rhs.chronologicalOrder
    }
}

final class AnnotationNode: Equatable, Hashable {
    var title: String
    var children: [AnnotationNode] = []
    var annotation: Annotation? // optional, kalau node ini representasi annotation
    var kind: AnnotationNodeKind

    init(
        title: String,
        kind: AnnotationNodeKind = .book,
        annotation: Annotation? = nil
    ) {
        self.title = title
        self.kind = kind
        self.annotation = annotation
    }

    func update(with annotation: Annotation) {
        if let note = annotation.note, !note.isEmpty {
            title = note
        } else {
            title = annotation.context
        }
        self.annotation = annotation
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    static func == (lhs: AnnotationNode, rhs: AnnotationNode) -> Bool {
        lhs === rhs
    }
}
