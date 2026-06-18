//
//  Navigation.swift
//  maktab
//
//  Created by MacBook on 30/11/25.
//

import Cocoa
import Combine

class Navigation: NSViewController {

    @IBOutlet weak var juzCurrent: NSTextField!
    @IBOutlet weak var juzMax: NSTextField!
    @IBOutlet weak var juzSlider: NSSlider!
    @IBOutlet weak var juzTextVStack: NSStackView!
    @IBOutlet weak var juzSliderVStack: NSStackView!
    @IBOutlet weak var hLine: NSBox!
    @IBOutlet weak var rootStackView: NSStackView!

    @IBOutlet weak var pageCurrent: NSTextField!
    @IBOutlet weak var pageMax: NSTextField!
    @IBOutlet weak var pageSlider: NSSlider!

    @IBOutlet weak var xBtn: NSButton!

    var viewModel: ReaderViewModel!
    var popover: Bool = true

    private var workItem: DispatchWorkItem?
    private var juzWorkItem: DispatchWorkItem?

    private var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        xBtn.isHidden = popover

        Publishers.Merge3(
            viewModel.$totalParts,
            viewModel.$minPageInPart,
            viewModel.$maxPageInPart
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.syncSlidersWithViewModel()
        }
        .store(in: &cancellables)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        viewModel.updateNavigationLimits()
    }

    func syncSlidersWithViewModel() {
        let totalJuz = max(1, viewModel.totalParts)
        let currentJuz = viewModel.currentPart ?? 1

        juzMax.stringValue = "\(totalJuz)"
        juzSlider.minValue = 1
        juzSlider.maxValue = Double(totalJuz)
        juzSlider.integerValue = currentJuz
        juzCurrent.stringValue = "\(currentJuz)"

        if juzSlider.numberOfTickMarks != totalJuz {
            juzSlider.numberOfTickMarks = totalJuz
            juzSlider.allowsTickMarkValuesOnly = true
        }

        let shouldHide = juzSlider.minValue == juzSlider.maxValue
        juzTextVStack.isHidden = shouldHide
        juzSliderVStack.isHidden = shouldHide
        hLine.isHidden = shouldHide

        let minPage = viewModel.minPageInPart
        let maxPage = max(minPage, viewModel.maxPageInPart)
        let currentPage = viewModel.currentPage ?? minPage

        pageMax.stringValue = "\(maxPage)"
        pageSlider.minValue = Double(minPage)
        pageSlider.maxValue = Double(maxPage)
        pageSlider.integerValue = currentPage
        pageCurrent.stringValue = "\(currentPage)"
        pageSlider.isContinuous = true
        
        rootStackView.layoutSubtreeIfNeeded()
    }

    @IBAction func pageSliderChanged(_ sender: NSSlider) {
        let pageNumber = sender.integerValue
        guard pageNumber != viewModel.currentPage else { return }
        pageCurrent.stringValue = "\(pageNumber)"

        workItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.viewModel.jumpToPage(pageNumber)
        }
        workItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    @IBAction func juzSliderChanged(_ sender: NSSlider) {
        let juzNumber = sender.integerValue
        guard juzNumber != viewModel.currentPart else { return }
        juzCurrent.stringValue = "\(juzNumber)"

        juzWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.viewModel.jumpToPart(juzNumber)
        }
        juzWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    deinit {
        cancellables.removeAll()
    }
}
