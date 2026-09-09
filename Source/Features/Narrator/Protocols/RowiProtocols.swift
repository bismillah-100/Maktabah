//
//  RowiProtocols.swift
//  Maktabah
//

import Foundation

@MainActor
protocol RowiSidebarDelegate: AnyObject, Sendable {
    func didSelect(rowi: Rowi)
}

@MainActor
protocol TarjamahBDelegate: AnyObject, Sendable {
    func didSelectRowi(rowi: Rowi)
    func didSelect(tarjamahB: TarjamahMen, query: String?) async
}
