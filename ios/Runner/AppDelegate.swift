import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private static let libraryFolderBookmarkKey = "aether.libraryFolderBookmark"
  private var pendingFolderPick: FlutterResult?
  private var activeFolderURL: URL?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AetherLibraryFolder") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "aether/library_folder",
      binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "pickFolder":
        self.pickLibraryFolder(result: result)
      case "restoreFolder":
        result(self.restoreLibraryFolder())
      case "iCloudDocuments":
        self.iCloudDocumentsDirectory(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func pickLibraryFolder(result: @escaping FlutterResult) {
    if pendingFolderPick != nil {
      result(FlutterError(code: "picker_busy", message: "A folder picker is already open.", details: nil))
      return
    }
    guard let presenter = topViewController() else {
      result(FlutterError(code: "no_presenter", message: "No screen available to show the picker.", details: nil))
      return
    }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    pendingFolderPick = result
    presenter.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    let result = pendingFolderPick
    pendingFolderPick = nil
    guard let url = urls.first else {
      result?(nil)
      return
    }
    do {
      result?(try adoptLibraryFolder(url))
    } catch {
      result?(FlutterError(code: "bookmark_failed", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = pendingFolderPick
    pendingFolderPick = nil
    result?(nil)
  }

  private func adoptLibraryFolder(_ url: URL) throws -> String {
    activeFolderURL?.stopAccessingSecurityScopedResource()
    _ = url.startAccessingSecurityScopedResource()
    let bookmark = try url.bookmarkData(
      options: [],
      includingResourceValuesForKeys: nil,
      relativeTo: nil)
    UserDefaults.standard.set(bookmark, forKey: Self.libraryFolderBookmarkKey)
    activeFolderURL = url
    return url.path
  }

  private func restoreLibraryFolder() -> String? {
    guard let bookmark = UserDefaults.standard.data(forKey: Self.libraryFolderBookmarkKey) else {
      return nil
    }
    var isStale = false
    guard let url = try? URL(
      resolvingBookmarkData: bookmark,
      options: [],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale)
    else {
      return nil
    }
    activeFolderURL?.stopAccessingSecurityScopedResource()
    _ = url.startAccessingSecurityScopedResource()
    activeFolderURL = url
    if isStale, let refreshed = try? url.bookmarkData(
      options: [],
      includingResourceValuesForKeys: nil,
      relativeTo: nil)
    {
      UserDefaults.standard.set(refreshed, forKey: Self.libraryFolderBookmarkKey)
    }
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return url.path
  }

  // The ubiquity container lookup blocks, so it runs off the main thread.
  private func iCloudDocumentsDirectory(result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      let documents = container.appendingPathComponent("Documents", isDirectory: true)
      do {
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        DispatchQueue.main.async { result(documents.path) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "icloud_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func topViewController() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    var top = windows.first { $0.isKeyWindow }?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
