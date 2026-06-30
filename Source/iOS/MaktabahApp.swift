import SwiftUI
import CloudKit

@main
struct MaktabahApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    static var isIpad: Bool {
        if UIDevice.current.userInterfaceIdiom == .pad {
            true
        } else {
            false
        }
    }

    var isDarkMode: Bool {
        TextViewState.shared.isDarkMode
    }

    /*
    @AppStorage("lastVersionPrompted") var lastVersionPrompted = ""
    @State private var showWelcomeScreen = false
     */

    @AppStorage("useDefaultTheme") private var useDefaultTheme: Bool = false

    /*
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
     */

    init() {
        AppConfig.initializeMode()
        ArabicFont.registerCustomFonts()
        UserFontManager.shared.registerUserFonts()
        AppConfig.setupAnnotationsAndResults()
        CloudKitSyncManager.shared.initializeOnLaunch()
        // CoreDatabaseBootstrap.run()
        setupGlobalAppearances()
        if UserDefaults.standard.data(forKey: AppConfig.annotationsAndResultsFolder) == nil {
            UserDefaults.standard.register(defaults: [AppConfig.useICloudKey: true])
        }
    }

    private func setupGlobalAppearances() {
        // -- Navigation Bar --
        if #unavailable(iOS 26) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            if !useDefaultTheme {
                appearance.backgroundColor = .appSecondaryBackground
            }

            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
        }
        UINavigationBar.appearance().tintColor = useDefaultTheme ? nil : UIColor.iosTint

        // -- Tab Bar --
        let barAppearance = UITabBarAppearance()
        barAppearance.configureWithDefaultBackground()
        if !useDefaultTheme {
            barAppearance.backgroundColor = .appSecondaryBackground
        }
        UITabBar.appearance().standardAppearance = barAppearance
    }

    var body: some Scene {
        WindowGroup {
            iOSBootstrapView()
                .applyIpadColorScheme(isIpad: Self.isIpad, isDarkMode: isDarkMode)
                .id(useDefaultTheme)
                .toggleStyle(SwitchToggleStyle(tint: .green))
                /*
                .onAppear {
                    if lastVersionPrompted != currentVersion {
                        showWelcomeScreen = true
                    }
                }
                .sheet(isPresented: $showWelcomeScreen) {
                    WelcomeScreenView(onDismiss: {
                        lastVersionPrompted = currentVersion
                        showWelcomeScreen = false
                    })
                    .interactiveDismissDisabled()
                }
                 */
                .onChange(of: useDefaultTheme) { _, _ in
                    setupGlobalAppearances()
                    // Force navigation bars and tab bars in all windows to redraw their appearances
                    for scene in UIApplication.shared.connectedScenes {
                        if let windowScene = scene as? UIWindowScene {
                            windowScene.windows.forEach { window in
                                for view in window.subviews {
                                    view.removeFromSuperview()
                                    window.addSubview(view)
                                }
                            }
                        }
                    }
                }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func applicationDidFinishLaunching(_ application: UIApplication) {
        application.registerForRemoteNotifications()
    }
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        CloudKitSyncManager.shared.fetchChanges()
        completionHandler(.newData)
    }
    func applicationWillTerminate(_ application: UIApplication) {
        CloudKitCoreManager.shared.syncWorker()
    }
}

extension View {
    @ViewBuilder
    func applyIpadColorScheme(isIpad: Bool, isDarkMode: Bool) -> some View {
        if isIpad {
            self.preferredColorScheme(isDarkMode ? .dark : .light)
        } else {
            self // Tidak menerapkan modifier apa-apa jika bukan iPad
        }
    }

    /// Menerapkan warna latar belakang tema utama aplikasi
    func themeBackground() -> some View {
        background(Color.appBackground)
    }

    /// Menerapkan warna latar belakang tema untuk baris di List
    func themeListRowBackground() -> some View {
        listRowBackground(Color.appCellBackground)
    }

    /// Helper untuk List: menyembunyikan background bawaan List dan menerapkan tema
    func themeListBackground() -> some View {
        listRowBackground(Color.appBackground)
    }
}

// MARK: - Color Theme Extensions

extension UIColor {
    static let appBackground = UIColor { traitCollection in
        if UserDefaults.standard.bool(forKey: "useDefaultTheme") {
            return .systemGroupedBackground
        }
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor.bgSepiaDark.adjustBrightness(to: 0.60)
        default:
            return UIColor(red: 237/255, green: 217/255, blue: 184/255, alpha: 1.0)
        }
    }

    static let appCellBackground = UIColor { traitCollection in
        if UserDefaults.standard.bool(forKey: "useDefaultTheme") {
            return .secondarySystemGroupedBackground
        }
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor.bgSepiaDark.adjustBrightness(to: 0.80)
        default:
            return UIColor.bgSepia
        }
    }

    static let appSecondaryBackground = UIColor { traitCollection in
        if UserDefaults.standard.bool(forKey: "useDefaultTheme") {
            return .secondarySystemBackground
        }
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor.bgSepiaDark.adjustBrightness(to: 0.85)
        default:
            // Mid-tone light sepia for toolbars / headers
            return UIColor(red: 229/255, green: 217/255, blue: 194/255, alpha: 1.0)
        }
    }

    /// Menyesuaikan brightness warna dengan rasio (0.0 - 1.0)
    func adjustBrightness(to ratio: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if self.getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
            return UIColor(hue: h, saturation: s, brightness: b * ratio, alpha: a)
        }
        var white: CGFloat = 0
        if self.getWhite(&white, alpha: &a) {
            return UIColor(white: white * ratio, alpha: a)
        }
        return self
    }
}

extension Color {
    static let appBackground = Color(uiColor: .appBackground)
    static let appCellBackground = Color(uiColor: .appCellBackground)
    static let appSecondaryBackground = Color(uiColor: .appSecondaryBackground)
}
