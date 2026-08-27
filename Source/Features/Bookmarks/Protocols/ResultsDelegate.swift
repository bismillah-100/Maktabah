//
//  ResultsDelegate.swift
//  Maktabah
//

import Foundation

protocol ResultsDelegate: AnyObject {
    func didSelect(savedResults: [SavedResultsItem])
}
