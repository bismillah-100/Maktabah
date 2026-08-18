//
//  AnVC+Search.swift
//  Maktabah
//

import Cocoa

extension AnnotationsVC: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let obj = obj.object as? DSFSearchField, obj === searchField else { return }
        searchField.stringValue.isEmpty
            ? removeScopePanelFromWindow()
            : updateAndShowScopePanel()
    }

    func updateAndShowScopePanel() {
        guard !scopePanel.isVisible else { return }

        scopeSegment.selectedSegment = dataSource.viewModel.searchScope.rawValue

        let fittingSize = scopeSegment.fittingSize
        let panelWidth = max(fittingSize.width + 16, searchField.bounds.width)
        let panelHeight = fittingSize.height + 12

        let bounds = searchField.bounds
        let rectInWindow = searchField.convert(bounds, to: nil)
        guard let screenRect = searchField.window?.convertToScreen(rectInWindow) else { return }

        let x = MainWindow.rtl ? (screenRect.maxX - panelWidth) : screenRect.minX
        let y = screenRect.minY - panelHeight - 8

        scopePanel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        view.window?.addChildWindow(scopePanel, ordered: .above)
    }

    @objc func searchScopeChanged(_ sender: NSSegmentedControl) {
        guard let scope = AnnotationSearchScope(rawValue: sender.selectedSegment) else { return }
        dataSource.viewModel.searchScope = scope
    }

    func removeScopePanelFromWindow() {
        guard let window = view.window,
              let windows = window.childWindows,
              windows.contains(scopePanel)
        else { return }
        scopePanel.orderOut(nil)
        window.removeChildWindow(scopePanel)
    }
}
