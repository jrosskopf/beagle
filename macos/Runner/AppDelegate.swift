import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var statusItem: NSStatusItem!
  private var popover: NSPopover!
  private var eventMonitor: Any?

  override func applicationDidFinishLaunching(_ aNotification: Notification) {
    super.applicationDidFinishLaunching(aNotification)
    NSApp.setActivationPolicy(.accessory)  // belt-and-suspenders alongside LSUIElement.

    // Build the popover hosting the existing Flutter view controller.
    popover = NSPopover()
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 360, height: 520)

    // Move the main window's contentViewController into the popover.
    if let mainWin = NSApp.windows.first(where: { $0.contentViewController is FlutterViewController }) {
      if let vc = mainWin.contentViewController {
        popover.contentViewController = vc
      }
      mainWin.orderOut(nil)
    }

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let btn = statusItem.button {
      btn.image = NSImage(systemSymbolName: "icloud.and.arrow.up", accessibilityDescription: "drive-beagle")
      btn.image?.isTemplate = true
      btn.action = #selector(togglePopover(_:))
      btn.target = self
    }

    // Click outside to dismiss.
    eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
      if self?.popover.isShown == true { self?.popover.performClose(nil) }
    }
  }

  @objc func togglePopover(_ sender: AnyObject?) {
    if popover.isShown {
      popover.performClose(sender)
    } else if let btn = statusItem.button {
      popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Keep running as a menu-bar agent.
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
