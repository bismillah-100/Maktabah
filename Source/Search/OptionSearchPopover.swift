import Cocoa

enum OptionSearchPopover {

    @discardableResult
    static func instantiatePopoverIfNeeded(_ currentPopover: inout NSPopover?) -> NSPopover {
        if let currentPopover {
            return currentPopover
        }
        let popover = NSPopover()
        popover.behavior = .transient
        currentPopover = popover
        return popover
    }

    @discardableResult
    static func instantiateSearchVCIfNeeded(_ currentVC: inout OptionSearchVC?) -> OptionSearchVC {
        if let currentVC {
            return currentVC
        }
        let vc = OptionSearchVC()
        vc.view.frame = NSRect(x: 0, y: 0, width: 350, height: 300)
        currentVC = vc
        return vc
    }

    static func present(
        popover: inout NSPopover?,
        searchVC: inout OptionSearchVC?,
        bookID: Any?,
        from sender: NSButton,
        delegate: OptionSearchDelegate?,
        onCleanUp: (() -> Void)? = nil
    ) {
        guard let rawId = bookID, let id = Int("\(rawId)") else {
            ReusableFunc.showAlert(
                title: String(localized: .noBookSelectedTitle),
                message: String(localized: .noBookSelectedDesc)
            )
            return
        }

        let pop = instantiatePopoverIfNeeded(&popover)
        let vc = instantiateSearchVCIfNeeded(&searchVC)

        vc.bkId = "b\(id)"
        pop.contentViewController = vc
        pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        vc.compactButton()

        vc.onSelectedItem = { [weak delegate] id, query, mode, nearDistance in
            Task.detached {
                await delegate?.didSelectResult(
                    for: id,
                    highlightText: query,
                    mode: mode,
                    nearDistance: Int(nearDistance) ?? 10
                )
            }
        }

        vc.onCleanUp = { [weak sender, weak pop] in
            if let sender {
                pop?.performClose(sender)
            } else {
                pop?.close()
            }
            onCleanUp?()
        }
    }
}
