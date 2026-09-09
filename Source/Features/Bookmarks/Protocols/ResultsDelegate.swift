//
//  ResultsDelegate.swift
//  Maktabah
//

import Foundation

@MainActor
protocol ResultsDelegate: AnyObject {
    func didSelect(savedResults: [SavedResultsItem])
}
