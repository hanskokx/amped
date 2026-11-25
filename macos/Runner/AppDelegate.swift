import Cocoa
import FlutterMacOS
import MediaPlayer
import UserNotifications
import UniformTypeIdentifiers

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  private let ampedChannelName = "amped"

  /// The single engine. Every window (main, equalizer, playlist, ...) is
  /// created from Dart through Flutter's windowing API, so the engine starts
  /// headless, without a window of its own.
  private var engine: FlutterEngine?

  private var aboutWindow: NSWindow?

  /// "Copyright © 2026 Hans Kokx. ..." with the years running up to the
  /// current one once it is later than 2026.
  private func copyrightLine() -> String {
    let first = 2026
    let year = Calendar.current.component(.year, from: Date())
    let years = year > first ? "\(first)–\(year)" : "\(first)"
    return "Copyright © \(years) Hans Kokx. All rights reserved."
  }

  /// A small About window like the standard panel, but with selectable
  /// version and git commit (stamped into Info.plist by the "Stamp Git
  /// Commit" build phase) so they can be copied.
  @objc func showAmpedAboutPanel(_ sender: Any?) {
    if let window = aboutWindow {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    func info(_ key: String) -> String {
      Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
    func label(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
      let field = NSTextField(labelWithString: text)
      field.font = font
      field.textColor = color
      field.alignment = .center
      field.isSelectable = true
      return field
    }

    var version = "Version \(info("CFBundleShortVersionString")) (\(info("CFBundleVersion")))"
    let commit = info("AmpedGitCommit")
    if !commit.isEmpty { version += "\n\(commit)" }

    let icon = NSImageView(image: NSImage(named: "AboutIcon") ?? NSApp.applicationIconImage)
    icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 96).isActive = true

    var views: [NSView] = [
      icon,
      label(info("CFBundleName"), font: .boldSystemFont(ofSize: 20)),
    ]
    if let tagline = nativeMenuLabels["ampedTagline"], !tagline.isEmpty {
      views.append(label(tagline, font: .systemFont(ofSize: 13), color: .secondaryLabelColor))
    }
    views += [
      label(version, font: .systemFont(ofSize: 12)),
      label(
        copyrightLine(), font: .systemFont(ofSize: 11),
        color: .secondaryLabelColor),
    ]
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 8
    stack.setCustomSpacing(16, after: icon)
    stack.translatesAutoresizingMaskIntoConstraints = false

    // Padding lives in a container so it holds whatever the window does.
    let content = NSView()
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 32),
      stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -28),
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 40),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -40),
    ])

    let window = NSWindow(
      contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.contentView = content
    window.setContentSize(content.fittingSize)
    window.center()
    aboutWindow = window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  /// Clicking the Dock icon with every window closed brings the main window
  /// back.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    // The switcher anchor does not count as a window the user can see.
    let visible = NSApp.windows.contains {
      $0.isVisible && !($0 is SwitcherAnchorWindow) && !($0 is NSPanel)
    }
    if !visible && dartReady { send("showMainWindow") }
    return true
  }

  /// Without a delegate macOS drops a notification while the app is in
  /// front; Amped wants the banner either way.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner])
  }

  /// Clicking a notification that carries episodes tells Dart, which does
  /// what the user chose for it.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
      let locations = response.notification.request.content.userInfo["locations"]
        as? [String], !locations.isEmpty, dartReady
    {
      send("notificationClicked", locations)
    }
    completionHandler()
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return false
  }

  override func applicationWillFinishLaunching(_ notification: Notification) {
    super.applicationWillFinishLaunching(notification)
    guard !activateExistingInstanceOrTerminate() else { return }
    migrateFromSandboxContainer()
    let engine = FlutterEngine(name: "amped", project: nil)
    RegisterGeneratedPlugins(registry: engine)
    // Register the menu channel before Dart starts so its startup menu-state
    // sync is not dropped.
    let channel = FlutterMethodChannel(
      name: ampedChannelName,
      binaryMessenger: engine.binaryMessenger
    )
    channel.setMethodCallHandler(handleMethodCall)
    ampedChannel = channel
    self.engine = engine
    setupDockMenu()
    setUpRemoteCommands()
    NotificationCenter.default.addObserver(
      self, selector: #selector(raiseAllWindows),
      name: NSApplication.didBecomeActiveNotification, object: nil)
    for name in [
      NSWindow.didResizeNotification,
      NSWindow.didChangeOcclusionStateNotification,
      NSWindow.didMiniaturizeNotification,
      NSWindow.didDeminiaturizeNotification,
    ] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(windowsChanged(_:)), name: name, object: nil)
    }
    engine.run(withEntrypoint: nil)
  }

  // MARK: - Cmd-Tab anchor

  /// macOS leaves an app out of the Cmd-Tab switcher when all its windows
  /// are short strips (somewhere between 40 and 60 points tall), which is
  /// what every window is in window shade mode. While that is the case, an
  /// invisible, click-through window keeps the app in the switcher.
  private let switcherMinHeight: CGFloat = 60
  private var switcherAnchor: SwitcherAnchorWindow?
  private var switcherUpdatePending = false

  @objc private func windowsChanged(_ note: Notification) {
    if note.object is SwitcherAnchorWindow || switcherUpdatePending { return }
    switcherUpdatePending = true
    DispatchQueue.main.async { [weak self] in
      self?.switcherUpdatePending = false
      self?.updateSwitcherAnchor()
    }
  }

  private func updateSwitcherAnchor() {
    let windows = NSApp.windows.filter {
      $0.isVisible && !$0.isMiniaturized && !($0 is SwitcherAnchorWindow) && !($0 is NSPanel)
    }
    let needed = !windows.isEmpty && windows.allSatisfy { $0.frame.height < switcherMinHeight }
    if needed {
      let anchor = switcherAnchor ?? SwitcherAnchorWindow()
      switcherAnchor = anchor
      if !anchor.isVisible {
        if let screen = NSScreen.main?.visibleFrame {
          anchor.setFrameOrigin(screen.origin)
        }
        anchor.orderBack(nil)
      }
    } else {
      switcherAnchor?.orderOut(nil)
    }
  }

  /// Switching to the app (Cmd-Tab, Dock, Mission Control) brings only the
  /// key window forward, leaving the equalizer and playlist behind other
  /// apps' windows. Like the classic player, raise them all together, keeping their
  /// stacking order among themselves.
  @objc private func raiseAllWindows() {
    raiseWindows()
    // Activating through Cmd-Tab is not finished when this notification
    // arrives: windows ordered front now still end up below the app that
    // was in front, and AppKit then keeps bringing the switcher anchor
    // forward for a moment. Raise again once that has settled.
    for delay in [0.1, 0.3] {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard NSApp.isActive else { return }
        self?.raiseWindows()
      }
    }
  }

  private func raiseWindows() {
    // Front to back; ordering front from the back keeps the relative order.
    // Minimized windows stay minimized.
    let windows = NSApp.orderedWindows.filter {
      $0.isVisible && !$0.isMiniaturized && !($0 is NSPanel) && !($0 is SwitcherAnchorWindow)
    }
    // While the switch is still settling, `orderFront` leaves a window
    // below the app that was in front; `orderFrontRegardless` does not.
    for window in windows.reversed() {
      window.orderFrontRegardless()
    }
    let key = NSApp.keyWindow
    if let key, windows.contains(key) {
      // The window the user was last in stays on top.
      key.orderFrontRegardless()
    } else if let front = windows.first, key == nil || key is SwitcherAnchorWindow {
      // No key window, or the anchor, which cannot take key: give it to a
      // real window instead.
      front.makeKeyAndOrderFront(nil)
    }
    switcherAnchor?.orderBack(nil)
  }

  /// Earlier builds ran sandboxed, keeping settings and installed skins in
  /// the app's container. Unsandboxed, the app uses the regular Library
  /// folders, so carry them over once.
  private func migrateFromSandboxContainer() {
    let defaults = UserDefaults.standard
    let migratedKey = "amped.migratedFromSandbox"
    guard !defaults.bool(forKey: migratedKey) else { return }
    defaults.set(true, forKey: migratedKey)
    let files = FileManager.default
    let bundleId = Bundle.main.bundleIdentifier ?? "org.hadak.amped"
    let container = files.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Containers/\(bundleId)/Data/Library")
    let oldPreferences = container.appendingPathComponent("Preferences/\(bundleId).plist")
    // The container holds the settings of the latest runs, so they win over
    // any left from older unsandboxed ones.
    if let old = NSDictionary(contentsOf: oldPreferences) as? [String: Any] {
      for (key, value) in old where key.hasPrefix("flutter.") {
        defaults.set(value, forKey: key)
      }
    }
    let oldSupport = container.appendingPathComponent("Application Support/\(bundleId)")
    if let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      copyMissing(from: oldSupport, to: support.appendingPathComponent(bundleId))
    }
  }

  /// Copies the files under [source] that [destination] does not have.
  private func copyMissing(from source: URL, to destination: URL) {
    let files = FileManager.default
    var isDirectory: ObjCBool = false
    guard files.fileExists(atPath: source.path, isDirectory: &isDirectory) else { return }
    if !isDirectory.boolValue {
      if !files.fileExists(atPath: destination.path) {
        try? files.copyItem(at: source, to: destination)
      }
      return
    }
    try? files.createDirectory(at: destination, withIntermediateDirectories: true)
    for name in (try? files.contentsOfDirectory(atPath: source.path)) ?? [] {
      copyMissing(
        from: source.appendingPathComponent(name),
        to: destination.appendingPathComponent(name))
    }
  }

  /// Quitting from the menu bar or the Dock lets Dart save the playlist and
  /// window layout first (it exits the process when done); a safety timer
  /// quits anyway if it does not answer.
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard dartReady, let channel = ampedChannel else { return .terminateNow }
    channel.invokeMethod("quit", arguments: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
      NSApp.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  /// Quits this instance if another copy of the app is already running, and
  /// activates the existing one. Without this, a second launch stacks a second
  /// set of windows (the windows are borderless with custom drag, so a stray
  /// main window cannot even be closed). Returns `true` when this instance
  /// terminated itself (i.e. the launch must stop), `false` to continue.
  private func activateExistingInstanceOrTerminate() -> Bool {
    let bundleId = Bundle.main.bundleIdentifier ?? ""
    if bundleId.isEmpty { return false }
    let selfPid = ProcessInfo.processInfo.processIdentifier
    let others = NSRunningApplication.runningApplications(
      withBundleIdentifier: bundleId
    ).filter { $0.processIdentifier != selfPid }
    guard let other = others.first else { return false }
    other.activate(options: [.activateIgnoringOtherApps])
    NSApp.terminate(nil)
    return true
  }

  /// The channel back to Dart. Dart reports state (always-on-top, EQ/PL open,
  /// UI scale) to update the matching menu checkmarks; menu items send
  /// commands.
  private var ampedChannel: FlutterMethodChannel?
  private var dockMenu: NSMenu?
  private var currentWindows: [[String: Any]] = []
  private var currentSkins: [String] = []
  /// The active skin's color themes (`names`, `current`, `shared`), when it has several.
  private var currentColorThemes: [String: Any]?
  private var currentActiveSkin: String?
  private var nativeMenuLabels: [String: String] = [:]
  private var isAlwaysOnTop = false
  private var isWindowShade = false
  private var currentUiScale: Double = 1.0


  /// Asks for permission to post notifications (a no-op once answered).
  private func requestNotificationPermission() {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.requestAuthorization(options: [.alert]) { _, _ in }
  }

  /// Posts a notification to Notification Center. A new one replaces the
  /// previous (same identifier), and the first asks for permission.
  private func showSystemNotification(
    title: String, body: String, image: String?, locations: [String]
  ) {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.requestAuthorization(options: [.alert]) { granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.userInfo = ["locations": locations]
      // Expanding the notification shows the cover in full.
      if let image = image,
        let attachment = try? UNNotificationAttachment(
          identifier: "cover", url: URL(fileURLWithPath: image))
      {
        content.attachments = [attachment]
      }
      center.add(
        UNNotificationRequest(
          identifier: "amped.track", content: content, trigger: nil))
    }
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setNativeMenuLabels":
      if let args = call.arguments as? [String: Any],
        let labels = args["labels"] as? [String: String] {
        nativeMenuLabels = labels
        applyNativeMenuLabels()
      }
      result(nil)
      refreshDockMenu()
    case "requestNotificationPermission":
      requestNotificationPermission()
      result(nil)
    case "showNotification":
      let args = call.arguments as? [String: Any] ?? [:]
      showSystemNotification(
        title: args["title"] as? String ?? "",
        body: args["body"] as? String ?? "",
        image: args["image"] as? String,
        locations: args["locations"] as? [String] ?? [])
      result(nil)
    case "setSkins":
      // The installed skins and the active one, for the Window > Skin menu.
      if let args = call.arguments as? [String: Any],
        let names = args["names"] as? [String] {
        currentColorThemes = args["colorThemes"] as? [String: Any]
        updateSkinMenu(names: names, active: args["active"] as? String)
        currentSkins = names
        currentActiveSkin = args["active"] as? String
      }
      result(nil)
      refreshDockMenu()
    case "openPanel":
      // The sandbox grants access to what the user picks here.
      let args = call.arguments as? [String: Any] ?? [:]
      let panel = NSOpenPanel()
      panel.title = args["title"] as? String ?? ""
      panel.allowsMultipleSelection = args["multiple"] as? Bool ?? true
      panel.canChooseFiles = args["files"] as? Bool ?? true
      panel.canChooseDirectories = args["directories"] as? Bool ?? false
      if let extensions = args["extensions"] as? [String], !extensions.isEmpty {
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
      }
      NSApp.activate(ignoringOtherApps: true)
      result(panel.runModal() == .OK ? panel.urls.map { $0.path } : [])
    case "savePanel":
      let args = call.arguments as? [String: Any] ?? [:]
      let panel = NSSavePanel()
      panel.title = args["title"] as? String ?? ""
      panel.nameFieldStringValue = args["name"] as? String ?? ""
      if let extensions = args["extensions"] as? [String], !extensions.isEmpty {
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
      }
      // A "Save as type" chooser ([[label, extension], ...]), like the
      // filter list of the Windows save dialog. The result then also says
      // which one was picked.
      var chooser: SaveFormatChooser?
      if let formats = args["formats"] as? [[String]], !formats.isEmpty {
        chooser = SaveFormatChooser(
          panel: panel, formats: formats,
          selected: (args["format"] as? NSNumber)?.intValue ?? 0,
          label: args["formatLabel"] as? String ?? "")
      }
      NSApp.activate(ignoringOtherApps: true)
      let path = panel.runModal() == .OK ? panel.url?.path : nil
      if let chooser {
        result(["path": path as Any, "format": chooser.selected])
      } else {
        result(path)
      }
    case "revealInFinder":
      let paths = call.arguments as? [String] ?? []
      NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
      result(nil)
    case "promptText":
      // A small modal text prompt (e.g. "Open URL").
      let args = call.arguments as? [String: Any] ?? [:]
      let alert = NSAlert()
      alert.messageText = args["title"] as? String ?? ""
      alert.informativeText = args["message"] as? String ?? ""
      alert.addButton(withTitle: args["confirmLabel"] as? String ?? "")
      alert.addButton(withTitle: args["cancelLabel"] as? String ?? "")
      let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
      // A one-line field that scrolls sideways: by default the cell wraps, so
      // a long pasted URL spills onto lines hidden below the 24pt frame and
      // looks cut off.
      field.usesSingleLineMode = true
      field.cell?.wraps = false
      field.cell?.isScrollable = true
      field.stringValue = args["value"] as? String ?? ""
      alert.accessoryView = field
      alert.window.initialFirstResponder = field
      NSApp.activate(ignoringOtherApps: true)
      result(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
    case "setNowPlaying":
      updateNowPlaying(call.arguments as? [String: Any] ?? [:])
      result(nil)
    case "setNowPlayingArtwork":
      updateArtwork((call.arguments as? FlutterStandardTypedData)?.data)
      result(nil)
    case "takePendingFiles":
      // Dart is listening from here on; hand over what arrived before.
      dartReady = true
      result(pendingFiles)
      pendingFiles = []
    case "setAlwaysOnTop":
      if let args = call.arguments as? [String: Any],
        let on = args["isAlwaysOnTop"] as? Bool {
        setMenuItemState(id: "win-always-on-top", title: menuLabel("alwaysOnTop"), on: on)
        isAlwaysOnTop = on
      }
      result(nil)
      refreshDockMenu()
    case "setWindowShade":
      if let args = call.arguments as? [String: Any], let on = args["on"] as? Bool {
        setMenuItemState(id: "win-window-shade", title: menuLabel("windowShade"), on: on)
        isWindowShade = on
      }
      result(nil)
      refreshDockMenu()
    case "setWindows":
      // The skinned windows and whether each is open, for Window > Windows.
      if let windows = call.arguments as? [[String: Any]] {
        updateWindowsMenu(windows)
        currentWindows = windows
      }
      result(nil)
      refreshDockMenu()
    case "setUiScale":
      if let args = call.arguments as? [String: Any], let scale = args["scale"] as? Double {
        setUiScaleMenuState(scale)
        currentUiScale = scale
      }
      result(nil)
      refreshDockMenu()
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func applyNativeMenuLabels() {
    let items = [
      ("amped.appMenu", "appName"),
      ("amped.about", "macAboutMenu"),
      ("amped.hide", "macHideMenu"),
      ("amped.preferences", "preferences"),
      ("amped.quit", "macQuitMenu"),
    ]
    for (identifier, key) in items {
      menuItem(identifier: identifier, in: NSApp.mainMenu)?.title =
        nativeMenuLabels[key] ?? ""
    }
    let localizedItems = [
      ("win-always-on-top", "Always on Top", "alwaysOnTop"),
      ("win-window-shade", "Window Shade", "windowShade"),
      ("win-windows", "Windows", "windows"),
      ("win-ui-scale", "Doublesize mode", "doubleSizeMode"),
      ("win-skin", "Skin", "skinMenu"),
    ]
    for (id, fallback, key) in localizedItems {
      let item = menuItem(id: id, title: fallback)
      item?.title = menuLabel(key)
      item?.submenu?.title = menuLabel(key)
    }
    dockMenu?.item(at: 0)?.title = menuLabel("windows")
    dockMenu?.item(at: 1)?.title = menuLabel("skins")
    dockMenu?.item(at: 2)?.title = menuLabel("settings")
  }

  private func menuItem(identifier: String, in menu: NSMenu?) -> NSMenuItem? {
    guard let menu else { return nil }
    for item in menu.items {
      if item.identifier?.rawValue == identifier { return item }
      if let match = menuItem(identifier: identifier, in: item.submenu) {
        return match
      }
    }
    return nil
  }

  private func menuLabel(_ key: String) -> String {
    nativeMenuLabels[key] ?? ""
  }

  private func setupDockMenu() {
    let dockMenu = NSMenu(title: "")
    
    // Windows Submenu
    let windowsMenu = NSMenu(title: menuLabel("windows"))
    let windowsItems = [
      (menuLabel("equalizer"), "win-eq"),
      (menuLabel("playlistEditor"), "win-pl"),
      (menuLabel("video"), "win-video"),
      (menuLabel("library"), "win-library"),
      (menuLabel("visualization"), "win-vis"),
      (menuLabel("albumArt"), "win-albumart")
    ]
    
    for (title, id) in windowsItems {
      let item = NSMenuItem(title: title, action: #selector(toggleWindowDockItem(_:)), keyEquivalent: "")
      item.representedObject = id
      item.target = self
      windowsMenu.addItem(item)
    }
    
    // Skins Submenu
    let skinsMenu = NSMenu(title: menuLabel("skins"))
    let skinBrowser = NSMenuItem(title: menuLabel("skinBrowser"), action: #selector(showSkinBrowser(_:)), keyEquivalent: "")
    skinBrowser.target = self
    skinsMenu.addItem(skinBrowser)
    skinsMenu.addItem(NSMenuItem.separator())
    
    // Settings Submenu
    let settingsMenu = NSMenu(title: menuLabel("settings"))
    let prefsItem = NSMenuItem(title: menuLabel("preferences"), action: #selector(showPreferences), keyEquivalent: "")
    prefsItem.target = self
    settingsMenu.addItem(prefsItem)
    
    let alwaysOnTopItem = NSMenuItem(title: menuLabel("alwaysOnTop"), action: #selector(toggleAlwaysOnTop), keyEquivalent: "")
    alwaysOnTopItem.target = self
    settingsMenu.addItem(alwaysOnTopItem)
    
    let windowShadeItem = NSMenuItem(title: menuLabel("windowShade"), action: #selector(toggleWindowShade), keyEquivalent: "")
    windowShadeItem.target = self
    settingsMenu.addItem(windowShadeItem)
    
    let doubleSizeItem = NSMenuItem(title: menuLabel("doubleSizeMode"), action: #selector(toggleUiScaleDock(_:)), keyEquivalent: "")
    doubleSizeItem.target = self
    settingsMenu.addItem(doubleSizeItem)
    
    // Assembly
    let windowsItem = NSMenuItem(title: menuLabel("windows"), action: nil, keyEquivalent: "")
    windowsItem.submenu = windowsMenu
    dockMenu.addItem(windowsItem)

    let skinsItem = NSMenuItem(title: menuLabel("skins"), action: nil, keyEquivalent: "")
    skinsItem.submenu = skinsMenu
    dockMenu.addItem(skinsItem)

    let settingsItem = NSMenuItem(title: menuLabel("settings"), action: nil, keyEquivalent: "")
    settingsItem.submenu = settingsMenu
    dockMenu.addItem(settingsItem)

    dockMenu.addItem(NSMenuItem.separator())
    
    let quitItem = NSMenuItem(title: menuLabel("quit"), action: #selector(quitApp), keyEquivalent: "q")
    quitItem.target = self
    dockMenu.addItem(quitItem)
    
    self.dockMenu = dockMenu
  }

  override func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    return dockMenu
  }

  private func refreshDockMenu() {
    guard let dockMenu = dockMenu else { return }
    // The Quit item was made before the labels arrived.
    dockMenu.items.last?.title = menuLabel("quit")
    
    // Windows Submenu
    guard let windowsMenu = dockMenu.item(at: 0)?.submenu else { return }
    windowsMenu.removeAllItems()
    let windowsItems = [
      (menuLabel("equalizer"), "win-eq"),
      (menuLabel("playlistEditor"), "win-pl"),
      (menuLabel("video"), "win-video"),
      (menuLabel("library"), "win-library"),
      (menuLabel("visualization"), "win-vis"),
      (menuLabel("albumArt"), "win-albumart")
    ]
    
    for (title, id) in windowsItems {
      let item = NSMenuItem(title: title, action: #selector(toggleWindowDockItem(_:)), keyEquivalent: "")
      item.representedObject = id
      item.target = self
      let key = id.replacingOccurrences(of: "win-", with: "")
      let isOpen = currentWindows.contains {
        $0["key"] as? String == key && $0["open"] as? Bool == true
      }
      item.state = isOpen ? .on : .off
      windowsMenu.addItem(item)
    }
    // The windows the skin brings of its own.
    let extras = currentWindows.filter { ($0["key"] as? String)?.hasPrefix("extra") == true }
    if !extras.isEmpty { windowsMenu.addItem(NSMenuItem.separator()) }
    for window in extras {
      guard let key = window["key"] as? String, let title = window["title"] as? String else { continue }
      let item = NSMenuItem(title: title, action: #selector(toggleWindowDockItem(_:)), keyEquivalent: "")
      item.representedObject = "win-" + key
      item.target = self
      item.state = window["open"] as? Bool == true ? .on : .off
      windowsMenu.addItem(item)
    }
    
    // Skins Submenu
    guard let skinsMenu = dockMenu.item(at: 1)?.submenu else { return }
    skinsMenu.removeAllItems()
    fillSkinsMenu(
      skinsMenu, names: currentSkins, active: currentActiveSkin, shortcut: false,
      selectSkin: #selector(selectSkinDock(_:)))

    // Settings Submenu
    guard let settingsMenu = dockMenu.item(at: 2)?.submenu else { return }
    settingsMenu.removeAllItems()
    
    let prefsItem = NSMenuItem(title: menuLabel("preferences"), action: #selector(showPreferences), keyEquivalent: "")
    prefsItem.target = self
    settingsMenu.addItem(prefsItem)
    
    let alwaysOnTopItem = NSMenuItem(title: menuLabel("alwaysOnTop"), action: #selector(toggleAlwaysOnTop), keyEquivalent: "")
    alwaysOnTopItem.target = self
    alwaysOnTopItem.state = isAlwaysOnTop ? .on : .off
    settingsMenu.addItem(alwaysOnTopItem)
    
    let windowShadeItem = NSMenuItem(title: menuLabel("windowShade"), action: #selector(toggleWindowShade), keyEquivalent: "")
    windowShadeItem.target = self
    windowShadeItem.state = isWindowShade ? .on : .off
    settingsMenu.addItem(windowShadeItem)
    
    let doubleSizeItem = NSMenuItem(title: menuLabel("doubleSizeMode"), action: #selector(toggleUiScaleDock(_:)), keyEquivalent: "")
    doubleSizeItem.target = self
    doubleSizeItem.state = (currentUiScale == 2.0) ? .on : .off
    settingsMenu.addItem(doubleSizeItem)
  }

  @objc private func toggleWindowDockItem(_ sender: NSMenuItem) {
    if let id = sender.representedObject as? String {
      let key: String
      switch id {
      case "win-eq": key = "eq"
      case "win-pl": key = "pl"
      case "win-video": key = "video"
      case "win-library": key = "library"
      case "win-vis": key = "vis"
      case "win-albumart": key = "albumart"
      default: key = id.hasPrefix("win-extra") ? String(id.dropFirst(4)) : ""
      }
      
      if !key.isEmpty {
        send("toggleWindow", key)
      }
    }
  }

  @objc private func toggleUiScaleDock(_ sender: NSMenuItem) {
    send("toggleUiScale")
  }

  @objc private func selectSkinDock(_ sender: NSMenuItem) {
    if let name = sender.representedObject as? String {
      send("selectSkin", name)
    }
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }

  private func setUiScaleMenuState(_ scale: Double) {
    setMenuItemState(id: "win-ui-scale", title: menuLabel("doubleSizeMode"), on: scale == 2.0)
    refreshDockMenu()
  }

  private func setMenuItemState(id: String, title: String, on: Bool) {
    menuItem(id: id, title: title)?.state = on ? .on : .off
  }

  private func menuItem(id: String, title: String) -> NSMenuItem? {
    guard let menu = NSApplication.shared.mainMenu else { return nil }
    return findMenuItem(id: id, title: title, in: menu)
  }

  private func findMenuItem(id: String, title: String, in menu: NSMenu) -> NSMenuItem? {
    for item in menu.items {
      if item.identifier?.rawValue == id || item.title == title {
        return item
      }
      if let submenu = item.submenu,
        let found = findMenuItem(id: id, title: title, in: submenu) {
        return found
      }
    }
    return nil
  }

  private func send(_ method: String, _ arguments: Any? = nil) {
    ampedChannel?.invokeMethod(method, arguments: arguments)
  }

  @IBAction func toggleAlwaysOnTop(_ sender: NSMenuItem) {
    send("toggleAlwaysOnTop")
  }

  @IBAction func toggleWindowShade(_ sender: NSMenuItem) {
    send("toggleWindowShade")
  }

  /// Rebuilds Window > Windows with one checkable item per skinned window,
  /// so a closed one (the main window too) can be opened again.
  private func updateWindowsMenu(_ windows: [[String: Any]]) {
    guard let menu = menuItem(id: "win-windows", title: menuLabel("windows"))?.submenu else { return }
    menu.removeAllItems()
    for window in windows {
      guard let key = window["key"] as? String, let title = window["title"] as? String
      else { continue }
      let item = NSMenuItem(
        title: title, action: #selector(toggleWindow(_:)),
        keyEquivalent: window["shortcut"] as? String ?? "")
      item.target = self
      item.representedObject = key
      item.state = window["open"] as? Bool == true ? .on : .off
      menu.addItem(item)
    }
    refreshDockMenu()
  }

  @objc func toggleWindow(_ sender: NSMenuItem) {
    if let key = sender.representedObject as? String {
      send("toggleWindow", key)
    }
  }


  @IBAction func toggleUiScale(_ sender: NSMenuItem) {
    send("toggleUiScale")
  }

  /// Rebuilds Window > Skin with one checkable item per installed skin.
  private func updateSkinMenu(names: [String], active: String?) {
    guard let menu = menuItem(id: "win-skin", title: menuLabel("skinMenu"))?.submenu else { return }
    menu.removeAllItems()
    fillSkinsMenu(
      menu, names: names, active: active, shortcut: true, selectSkin: #selector(selectSkin(_:)))
    refreshDockMenu()
  }

  /// Fills [menu] with the Skins entries of the main menu: the skin browsers,
  /// the installed skins and the active skin's color themes.
  private func fillSkinsMenu(
    _ menu: NSMenu, names: [String], active: String?, shortcut: Bool,
    selectSkin: Selector
  ) {
    let browser = NSMenuItem(
      title: menuLabel("skinBrowser"), action: #selector(showSkinBrowser(_:)),
      keyEquivalent: shortcut ? "s" : "")
    if shortcut { browser.keyEquivalentModifierMask = [.option] }
    browser.target = self
    menu.addItem(browser)
    let online = NSMenuItem(
      title: menuLabel("onlineSkinBrowser"), action: #selector(showOnlineSkinBrowser(_:)),
      keyEquivalent: "")
    online.target = self
    menu.addItem(online)
    menu.addItem(NSMenuItem.separator())
    for name in names {
      let item = NSMenuItem(title: name, action: selectSkin, keyEquivalent: "")
      item.target = self
      item.representedObject = name
      item.state = name == active ? .on : .off
      menu.addItem(item)
    }
    guard let themes = currentColorThemes, let themeNames = themes["names"] as? [String]
    else { return }
    menu.addItem(NSMenuItem.separator())
    let submenu = NSMenu(title: menuLabel("colorThemes"))
    let current = themes["current"] as? String
    for name in themeNames {
      let item = NSMenuItem(
        title: name, action: #selector(selectColorTheme(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = name
      item.state = name == current ? .on : .off
      submenu.addItem(item)
    }
    submenu.addItem(NSMenuItem.separator())
    let share = NSMenuItem(
      title: menuLabel("shareColorThemes"), action: #selector(shareColorThemes(_:)),
      keyEquivalent: "")
    share.target = self
    share.state = themes["shared"] as? Bool == true ? .on : .off
    submenu.addItem(share)
    let parent = NSMenuItem(title: menuLabel("colorThemes"), action: nil, keyEquivalent: "")
    parent.submenu = submenu
    menu.addItem(parent)
  }

  @objc func showSkinBrowser(_ sender: NSMenuItem) {
    send("skinBrowser")
  }

  @objc func showOnlineSkinBrowser(_ sender: NSMenuItem) {
    send("onlineSkinBrowser")
  }

  @objc func selectColorTheme(_ sender: NSMenuItem) {
    if let name = sender.representedObject as? String {
      send("selectColorTheme", name)
    }
  }

  @objc func shareColorThemes(_ sender: NSMenuItem) {
    send("shareColorThemes")
  }

  @objc func selectSkin(_ sender: NSMenuItem) {
    if let name = sender.representedObject as? String {
      send("selectSkin", name)
    }
  }

  // MARK: - Now Playing

  /// The media keys, Control Center, AirPods and the lock screen send
  /// commands to the app registered as the Now Playing player.
  private func setUpRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()
    let commands: [(MPRemoteCommand, String)] = [
      (center.playCommand, "play"),
      (center.pauseCommand, "pause"),
      (center.togglePlayPauseCommand, "togglePlayPause"),
      (center.stopCommand, "stop"),
      (center.nextTrackCommand, "next"),
      (center.previousTrackCommand, "previous"),
    ]
    for (command, name) in commands {
      command.isEnabled = true
      command.addTarget { [weak self] _ in
        self?.send("remoteCommand", ["command": name])
        return .success
      }
    }
    center.changePlaybackPositionCommand.isEnabled = true
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      self?.send("remoteCommand", ["command": "seek", "position": event.positionTime])
      return .success
    }
  }

  private var artwork: MPMediaItemArtwork?

  private func updateNowPlaying(_ args: [String: Any]) {
    let center = MPNowPlayingInfoCenter.default()
    let state = args["state"] as? String ?? "stopped"
    guard state != "stopped" || args["title"] is String else {
      center.nowPlayingInfo = nil
      center.playbackState = .stopped
      return
    }
    var info: [String: Any] = [
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: (args["elapsed"] as? NSNumber)?.doubleValue ?? 0,
      MPNowPlayingInfoPropertyPlaybackRate: state == "playing" ? 1.0 : 0.0,
    ]
    if let title = args["title"] as? String { info[MPMediaItemPropertyTitle] = title }
    if let artist = args["artist"] as? String { info[MPMediaItemPropertyArtist] = artist }
    if let album = args["album"] as? String { info[MPMediaItemPropertyAlbumTitle] = album }
    if let duration = (args["duration"] as? NSNumber)?.doubleValue {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    if let artwork = artwork { info[MPMediaItemPropertyArtwork] = artwork }
    center.nowPlayingInfo = info
    center.playbackState = state == "playing" ? .playing : state == "paused" ? .paused : .stopped
  }

  private func updateArtwork(_ data: Data?) {
    if let data = data, let image = NSImage(data: data) {
      artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    } else {
      artwork = nil
    }
    let center = MPNowPlayingInfoCenter.default()
    guard var info = center.nowPlayingInfo else { return }
    info[MPMediaItemPropertyArtwork] = artwork
    center.nowPlayingInfo = info
  }

  @IBAction func showPreferences(_ sender: NSMenuItem) {
    send("preferences")
  }

  // MARK: - Opening skins

  /// Skin files opened before Dart asked for them (e.g. the file that launched
  /// the app).
  private var pendingFiles: [String] = []
  private var dartReady = false

  /// Finder "Open", double-clicking a skin, track or playlist, and dropping
  /// files on the dock icon all arrive here; Dart decides what to do by type.
  override func application(_ application: NSApplication, open urls: [URL]) {
    let files = urls.filter { $0.isFileURL }
    let others = urls.filter { !$0.isFileURL }
    if !others.isEmpty { super.application(application, open: others) }
    let paths = files.map { $0.path }
    if paths.isEmpty { return }
    if dartReady {
      send("openFiles", paths)
    } else {
      pendingFiles.append(contentsOf: paths)
    }
  }
}

/// The invisible window that keeps the app in the Cmd-Tab switcher while
/// every real window is window-shaded (see `updateSwitcherAnchor`). Nearly
/// transparent rather than fully: 1% opacity is what was confirmed to keep
/// the app in the switcher.
final class SwitcherAnchorWindow: NSWindow {
  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: [.borderless], backing: .buffered, defer: false)
    isReleasedWhenClosed = false
    backgroundColor = .black
    alphaValue = 0.01
    hasShadow = false
    ignoresMouseEvents = true
    isExcludedFromWindowsMenu = true
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// The format popup of a save panel: picking a format changes the extension
/// of the file name.
final class SaveFormatChooser: NSObject {
  private weak var panel: NSSavePanel?
  private let formats: [[String]]
  private let popup = NSPopUpButton()

  init(panel: NSSavePanel, formats: [[String]], selected: Int, label: String) {
    self.panel = panel
    self.formats = formats
    super.init()
    for format in formats { popup.addItem(withTitle: format[0]) }
    popup.selectItem(at: min(max(selected, 0), formats.count - 1))
    popup.target = self
    popup.action = #selector(changed)
    let formatLabel = NSTextField(labelWithString: label)
    let row = NSStackView(views: [formatLabel, popup])
    row.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    panel.accessoryView = row
    objc_setAssociatedObject(panel, Unmanaged.passUnretained(self).toOpaque(), self, .OBJC_ASSOCIATION_RETAIN)
    apply()
  }

  var selected: Int { popup.indexOfSelectedItem }

  @objc private func changed() { apply() }

  private func apply() {
    guard let panel else { return }
    let ext = formats[selected][1]
    panel.allowedContentTypes = UTType(filenameExtension: ext).map { [$0] } ?? []
    let name = (panel.nameFieldStringValue as NSString).deletingPathExtension
    panel.nameFieldStringValue = "\(name).\(ext)"
  }
}
