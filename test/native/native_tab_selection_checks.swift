import Flutter
import UIKit

/// A standalone simulator probe. The runner compiles this with the production
/// SceneDelegate.swift, so the checks exercise its actual channels and delegates.
private final class RecordingTabMessenger: NSObject, FlutterBinaryMessenger {
  private let codec = FlutterStandardMethodCodec.sharedInstance()
  private var handlers: [String: FlutterBinaryMessageHandler] = [:]
  private(set) var calls: [FlutterMethodCall] = []
  var holdActionReplies = false
  private var heldActionReplies: [FlutterBinaryReply] = []

  func send(onChannel channel: String, message: Data?) {
    if let message { calls.append(codec.decodeMethodCall(message)) }
  }

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    send(onChannel: channel, message: message)
    if holdActionReplies, let message, codec.decodeMethodCall(message).method == "homeToolAction",
      let callback
    {
      heldActionReplies.append(callback)
      return
    }
    callback?(codec.encodeSuccessEnvelope(nil))
  }

  func setMessageHandlerOnChannel(
    _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection {
    handlers[channel] = handler
    return 1
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}

  func invoke(_ method: String, arguments: Any?) {
    let data = codec.encode(FlutterMethodCall(methodName: method, arguments: arguments))
    handlers["piliplus/native_tab_bar"]?(data, { _ in })
  }

  func clear() { calls.removeAll() }
  func completeActionReplies() {
    let callbacks = heldActionReplies
    heldActionReplies.removeAll()
    callbacks.forEach { $0(codec.encodeSuccessEnvelope(nil)) }
  }
  func arguments(for method: String) -> [Any?] {
    calls.filter { $0.method == method }.map(\.arguments)
  }
}

/// The real Flutter controller and framework are used, but no Dart isolate or
/// renderer is needed to verify UIKit containment and native channel messages.
private final class TabProbeFlutterController: FlutterViewController {
  let recordingMessenger: RecordingTabMessenger

  init(messenger: RecordingTabMessenger) {
    recordingMessenger = messenger
    super.init(project: FlutterDartProject(precompiledDartBundle: .main), nibName: nil, bundle: nil)
  }

  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override var binaryMessenger: FlutterBinaryMessenger { recordingMessenger }
  override func loadView() { view = UIView() }
}

@available(iOS 26.0, *)
private final class TabSelectionFixture {
  let messenger = RecordingTabMessenger()
  let flutter: TabProbeFlutterController
  let tabs: NativeTabBarController

  init(selected: Int = 0) {
    flutter = TabProbeFlutterController(messenger: messenger)
    tabs = NativeTabBarController(flutterViewController: flutter)
    messenger.invoke("setTabs", arguments: [
      "tabs": [
        ["id": "home", "title": "Home"],
        ["id": "dynamics", "title": "Dynamics"],
        ["id": "mine", "title": "Mine"],
      ],
      "selected": selected,
    ])
    homeTools()
    messenger.clear()
  }

  var hosts: [UIViewController] { Array(tabs.viewControllers!.prefix(3)) }
  var search: UIViewController { tabs.viewControllers![3] }

  func homeTools(badge: String? = nil, shown: Bool = true) {
    var search: [String: Any] = ["id": "search", "title": "Search"]
    if let badge { search["badge"] = badge }
    messenger.invoke("setHomeToolTabs", arguments: [
      "tabs": shown ? [search, ["id": "notifications", "title": "Messages"]] : [],
    ])
  }

  func selectPage(_ index: Int) throws {
    let host = hosts[index]
    try check(tabs.tabBarController(tabs, shouldSelect: host), "Root page was rejected")
    tabs.selectedViewController = host
    tabs.tabBarController(tabs, didSelect: host)
  }
}

private struct TabCheckFailure: Error, CustomStringConvertible {
  let description: String
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  if !condition() { throw TabCheckFailure(description: message) }
}

@available(iOS 26.0, *)
private func runTabSelectionChecks() -> [String: Any] {
  var passed: [String] = []
  var failed: [[String: String]] = []
  func run(_ name: String, _ body: () throws -> Void) {
    do {
      try body()
      passed.append(name)
    } catch {
      failed.append(["name": name, "error": String(describing: error)])
    }
  }

  run("Page selection embeds Flutter and publishes the root index") {
    let f = TabSelectionFixture()
    try f.selectPage(1)
    try check(f.tabs.selectedViewController === f.hosts[1], "Wrong selected root host")
    try check(f.flutter.parent === f.hosts[1], "Flutter remained in a different root host")
    try check(f.messenger.arguments(for: "select").compactMap { $0 as? Int } == [1],
      "Root selection did not publish exactly index 1")
  }

  run("Action selection invokes its command without selecting a page") {
    let f = TabSelectionFixture()
    let oldHost = f.tabs.selectedViewController
    try check(!f.tabs.tabBarController(f.tabs, shouldSelect: f.search), "Action was selectable")
    try check(f.tabs.selectedViewController === oldHost, "Action changed the selected root")
    try check(f.flutter.parent === oldHost, "Action detached Flutter from the root")
    try check(f.messenger.arguments(for: "homeToolAction").compactMap { $0 as? String } == ["search"],
      "Search was not dispatched exactly once")
    try check(f.messenger.arguments(for: "select").isEmpty, "Action published a page index")
  }

  run("Unknown controllers are rejected before they can show empty content") {
    let f = TabSelectionFixture()
    try check(!f.tabs.tabBarController(f.tabs, shouldSelect: UIViewController()),
      "An unknown controller was accepted as a page")
  }

  run("Badge refresh retains the action controller and root containment") {
    let f = TabSelectionFixture()
    let search = f.search
    try f.selectPage(1)
    f.messenger.clear()
    f.homeTools(badge: "7")
    try check(f.search === search, "A badge-only refresh replaced the action controller")
    try check(f.search.tabBarItem.badgeValue == "7", "Badge was not updated")
    try check(f.tabs.selectedViewController === f.hosts[1], "Refresh changed the root selection")
    try check(f.flutter.parent === f.hosts[1], "Refresh left the selected host empty")
    try check(f.messenger.arguments(for: "select").isEmpty, "Refresh published a user selection")
  }

  run("A retired action controller stays an action and is never accepted as a page") {
    let f = TabSelectionFixture()
    let retiredSearch = f.search
    f.homeTools(shown: false)
    f.messenger.clear()
    try check(!f.tabs.tabBarController(f.tabs, shouldSelect: retiredSearch),
      "A delayed callback for a retired action was accepted as a page")
    try check(f.messenger.arguments(for: "select").isEmpty, "Retired action published a root index")
    try check(f.messenger.arguments(for: "homeToolAction").isEmpty,
      "A removed action still dispatched a command")
  }

  for actionIndex in [3, 4] {
    run("Escaped action index \(actionIndex) restores the last root without publishing a page index") {
      let f = TabSelectionFixture()
      try f.selectPage(1)
      let originalHost = f.hosts[1]
      let action = f.tabs.viewControllers![actionIndex]
      f.messenger.clear()
      f.tabs.selectedViewController = action
      f.tabs.tabBarController(f.tabs, didSelect: action)
      try check(f.tabs.selectedViewController === originalHost, "Escaped action was left selected")
      try check(f.flutter.parent === originalHost, "Restored root did not contain Flutter")
      try check(f.messenger.arguments(for: "select").isEmpty, "Escaped action published a page index")
      let id = actionIndex == 3 ? "search" : "notifications"
      try check(f.messenger.arguments(for: "homeToolAction").compactMap { $0 as? String } == [id],
        "Escaped action did not dispatch its command exactly once")
    }
  }

  run("Duplicate delegate reports dispatch one command until Flutter replies") {
    let f = TabSelectionFixture()
    f.messenger.holdActionReplies = true
    let action = f.search
    let tab = UITab(title: "Search", image: nil, identifier: "search") { _ in action }
    try check(!f.tabs.tabBarController(f.tabs, shouldSelect: action), "Legacy action was selectable")
    try check(!f.tabs.tabBarController(f.tabs, shouldSelect: action), "Repeated action was selectable")
    _ = f.tabs.delegate?.tabBarController?(f.tabs, shouldSelectTab: tab)
    f.tabs.selectedViewController = action
    f.tabs.tabBarController(f.tabs, didSelect: action)
    try check(f.messenger.arguments(for: "homeToolAction").count == 1,
      "Overlapping callbacks dispatched a command more than once")
    f.messenger.completeActionReplies()
    try check(!f.tabs.tabBarController(f.tabs, shouldSelect: action), "Action was selectable after reply")
    try check(f.messenger.arguments(for: "homeToolAction").count == 2,
      "A later deliberate action was lost after the first command completed")
    f.messenger.completeActionReplies()
  }

  run("Removing tools after an escaped selection restores the original root") {
    let f = TabSelectionFixture()
    try f.selectPage(1)
    let originalHost = f.hosts[1]
    f.tabs.selectedViewController = f.search
    f.messenger.clear()
    f.homeTools(shown: false)
    try check(f.tabs.selectedViewController === originalHost,
      "Tool removal clamped the action index to a different root")
    try check(f.flutter.parent === originalHost, "Tool removal left an empty selected host")
  }

  run("A repeated setSelected repairs Flutter containment even when its index is unchanged") {
    let f = TabSelectionFixture()
    let originalHost = f.hosts[0]
    try check(f.tabs.tabBarController(f.tabs, shouldSelect: f.hosts[1]), "Root page was rejected")
    f.messenger.invoke("setSelected", arguments: 0)
    try check(f.tabs.selectedViewController === originalHost, "setSelected changed the wrong page")
    try check(f.flutter.parent === originalHost, "Repeated setSelected left Flutter in another host")
  }

  run("Modern action callbacks share the legacy interception") {
    let f = TabSelectionFixture()
    let search = f.search
    let tab = UITab(title: "Search", image: nil, identifier: "search") { _ in search }
    let accepted = f.tabs.delegate?.tabBarController?(f.tabs, shouldSelectTab: tab)
    try check(accepted == false, "Modern action callback did not reject the action")
    try check(f.messenger.arguments(for: "homeToolAction").compactMap { $0 as? String } == ["search"],
      "Modern action callback did not dispatch search exactly once")
    try check(f.messenger.arguments(for: "select").isEmpty, "Modern action published a root index")
  }

  run("Modern page callbacks embed Flutter and publish a valid root index") {
    let f = TabSelectionFixture()
    let host = f.hosts[2]
    let tab = UITab(title: "Mine", image: nil, identifier: "mine") { _ in host }
    try check(f.tabs.delegate?.tabBarController?(f.tabs, shouldSelectTab: tab) == true,
      "Modern page callback did not accept the root")
    f.tabs.selectedViewController = host
    f.tabs.delegate?.tabBarController?(f.tabs, didSelectTab: tab, previousTab: nil)
    try check(f.flutter.parent === host, "Modern selection left Flutter in another host")
    try check(f.messenger.arguments(for: "select").compactMap { $0 as? Int } == [2],
      "Modern page callback did not publish exactly index 2")
  }

  // The pre-fix implementation traps on a negative index. Baseline mode skips
  // only this crashing case so it can report all of the other regressions.
  if !ProcessInfo.processInfo.arguments.contains("--baseline") {
    run("A negative initial selection resolves to the first root") {
      let f = TabSelectionFixture(selected: -1)
      try check(f.tabs.selectedViewController === f.hosts[0], "Negative selection chose the wrong root")
      try check(f.flutter.parent === f.hosts[0], "First root did not contain Flutter")
    }
  }
  return ["passed": passed, "failed": failed]
}

@main
private final class NativeTabChecksApp: UIResponder, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool { true }
}

@objc(NativeTabChecksSceneDelegate)
private final class NativeTabChecksSceneDelegate: UIResponder, UIWindowSceneDelegate {
  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    DispatchQueue.main.async {
      guard #available(iOS 26.0, *) else { exit(2) }
      let result = runTabSelectionChecks()
      let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
      print("PILIPLUS_NATIVE_TAB_CHECKS=" + String(decoding: data, as: UTF8.self))
      fflush(stdout)
      exit((result["failed"] as! [[String: String]]).isEmpty ? 0 : 1)
    }
  }
}
