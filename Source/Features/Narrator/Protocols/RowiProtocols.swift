//
//  RowiProtocols.swift
//  Maktabah
//

import Foundation

protocol RowiSidebarDelegate: AnyObject {
    func didSelect(rowi: Rowi)
}

protocol TarjamahBDelegate: AnyObject {
    func didSelectRowi(rowi: Rowi)
    func didSelect(tarjamahB: TarjamahMen, query: String?) async
}
