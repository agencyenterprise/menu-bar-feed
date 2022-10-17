import Cocoa
import Combine
import SwiftUI
import LaunchAtLogin

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var cancellables = Set<AnyCancellable>()
    var statusItem: NSStatusItem?
    var menuManager: MenuManager?
    
    let viewModel = FeedListViewModel()
    
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var silenceFeedMenuItem: NSMenuItem!
    
    private var silenceFeedTimer = Timer
        .publish(every: Constants.silenceFeedPeriod, tolerance: 0.5, on: .main, in: .common).autoconnect()
    private var silenceFeedTimerCancellable: AnyCancellable?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.menu = statusMenu
        
        viewModel.$currentFeedItemTitle
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] title in
                guard let self = self else { return }
                self.statusItem?.button?.title = title
                self.statusItem?.button?.image = nil
            }
            .store(in: &cancellables)
        
        viewModel.$menuBarMaxCharactersSubject
            .receive(on: DispatchQueue.main)
            .debounce(for: 0.2, scheduler: DispatchQueue.main)
            .sink { [weak self] maxChars in
                guard let self = self else { return }
                let newLength = max(Constants.minMenuBarCharacters, maxChars)
                UserDefaults.standard.set(newLength, forKey: Constants.menuBarMaxCharactersKey)
                self.statusItem?.button?.title = self.viewModel.croppedTitle(self.statusItem?.button?.title ?? "")
            }
            .store(in: &cancellables)
        
        menuManager = MenuManager(statusMenu: statusMenu, viewModel: viewModel)
        statusMenu.delegate = menuManager
        
        Task {
            await viewModel.fetchAll()
        }
        
        // Un-comment this to print out the app location
        // print(Bundle.main.bundlePath)
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    @IBAction func openPreferences(_ sender: Any) {
        let hostingController = NSHostingController(
            rootView: PreferencesView(viewModel: viewModel).frame(width: Constants.preferencesMenuWidth, height: Constants.preferencesMenuHeight)
        )
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Preferences"
        
        let controller = NSWindowController(window: window)
        
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }
    
    @IBAction func onSilenceFeedTapped(_ sender: Any) {
        viewModel.onSilenceFeedTapped()
        
        if viewModel.isFeedSilenced {
            silenceFeedMenuItem.state = .on
            silenceFeedTimerCancellable?.cancel()
            silenceFeedTimerCancellable = nil
            silenceFeedTimerCancellable = silenceFeedTimer
                .sink(receiveValue: { [weak self] _ in
                    guard let self = self else { return }
                    self.onSilenceFeedTapped(self.silenceFeedMenuItem!)
                })
            
            statusItem?.button?.title = ""
            let statusImage = NSImage(imageLiteralResourceName: "menuIcon")
            statusImage.size = NSMakeSize(20, 16);
            statusItem?.button?.image = statusImage
        } else {
            statusItem?.button?.image = nil
            silenceFeedMenuItem.state = .off
            silenceFeedTimerCancellable?.cancel()
            silenceFeedTimerCancellable = nil
            
            Task {
                await viewModel.fetchAll()
            }
        }
    }
    
    @IBAction func openInBrowser(_ sender: Any) {
        guard let currentItem = viewModel.currentFeedItem else { return }
        NSWorkspace.shared.open(URL(string: currentItem.item.url)!)
    }
}
