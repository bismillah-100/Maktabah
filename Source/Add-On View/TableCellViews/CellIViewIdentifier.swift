//
//  CellIViewIdentifier.swift
//  maktab
//
//  Created by MacBook on 12/12/25.
//

import Foundation

enum CellIViewIdentifier: String {
    case resultAndOutlineChild = "DataCell"
    case resultNib = "Result"
    case outlineChildNib = "Data"
    case outlineParentNib = "Header"
    case outlineParent = "HeaderCell"
    case bookmarkParent = "FolderCell"
    case bookmarkParentNib = "FolderCellView"
    case bookmarkChild = "ResultCell"
    case bookmarkChildNib = "ResultCellView"
    case searchCellNib = "SearchCellView"
    case searchCell = "searchCellView"
}
