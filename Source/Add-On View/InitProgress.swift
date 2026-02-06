//
//  InitProgress.swift
//  Data SDI
//
//  Created by Bismillah on 17/11/24.
//

import Cocoa

/// Class untuk menampilkan tampilan awal dengan efek visual dan indikator progres.
/// Digunakan untuk menampilkan proses inisialisasi atau pemuatan data pada aplikasi.
class InitProgress: NSViewController {
    /// Outlet untuk ITProgressIndicator yang menampilkan indikator.
    @IBOutlet weak var indicator: NSProgressIndicator!
    override func loadView() {
        super.loadView()
        indicator.wantsLayer = true
        indicator.startAnimation(nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }
}
