import Flutter
import UIKit
import LocalAuthentication
import AVFoundation
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

// Pure URL policy, shared by authenticated downloads/uploads and unit tests.
enum LetianURLRules {
    static func web(_ value: String) -> URLComponents? {
        guard let c = URLComponents(string: value), let scheme = c.scheme?.lowercased(),
              ["https", "http"].contains(scheme), let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.port == nil || (1...65535).contains(c.port!) else { return nil }
        return c
    }
    static func sameOrigin(_ value: String, _ base: String) -> Bool {
        guard let a = web(value), let b = web(base), a.scheme?.lowercased() == "https",
              b.scheme?.lowercased() == "https", a.host?.lowercased() == b.host?.lowercased() else { return false }
        return (a.port ?? 443) == (b.port ?? 443)
    }
    static func external(_ value: String) -> URL? {
        guard let c = URLComponents(string: value), let s = c.scheme?.lowercased(),
              c.user == nil, c.password == nil else { return nil }
        if ["https", "http"].contains(s) { return web(value)?.url }
        return ["weixin", "snssdk1128", "dianping"].contains(s) ? c.url : nil
    }
}

// Redirects are rejected even within the same origin. Tokens never reach another origin.
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

final class LetianNative: NSObject, FlutterPlugin, UIImagePickerControllerDelegate,
    UINavigationControllerDelegate, PHPickerViewControllerDelegate, UIDocumentPickerDelegate,
    QLPreviewControllerDataSource, QLPreviewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    private let presenter: () -> UIViewController?
    private var config: [String: Any] = [:]
    private var photoReply: FlutterResult?
    private var treeReply: FlutterResult?
    private var fileReply: FlutterResult?
    private var previewFile: URL?
    private weak var currentPreview: QLPreviewController?
    private var activeDownload: URLSessionDownloadTask?
    private var downloadAlert: UIAlertController?
    private var fileOperationID: UUID?
    private var fileBusy = false
    private var syncBusy = false
    private var authBusy = false
    private let defaults = UserDefaults.standard
    private let noRedirect = NoRedirect()
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 180
        c.httpCookieStorage = nil
        c.urlCache = nil
        return URLSession(configuration: c, delegate: noRedirect, delegateQueue: nil)
    }()
    private let photoLimit = 15 * 1024 * 1024

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = LetianNative(presenter: { registrar.viewController })
        let key = registrar.lookupKey(forAsset: "assets/runtime-config.json")
        if let path = Bundle.main.path(forResource: key, ofType: nil),
           let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let raw = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
            let allowed: Set<String> = ["schema_version", "api_base_url", "update_manifest_url", "authorization_url", "subscription_url", "deals_authorization_url", "minis_url", "minis_download_url", "app_store_url"]
            if Set(raw.keys).isSubset(of: allowed), raw["schema_version"] as? Int == 1,
               let api = raw["api_base_url"] as? String, let c = LetianURLRules.web(api),
               c.scheme == "https", c.query == nil, c.fragment == nil,
               c.path.isEmpty || c.path == "/", c.host != "example.invalid" { instance.config = raw }
        }
        for name in ["install", "sys", "camera", "minis", "sync"] {
            let channel = FlutterMethodChannel(name: "site.zhangyue.vault/" + name, binaryMessenger: registrar.messenger())
            channel.setMethodCallHandler { [instance] call, result in instance.handle(name, call, result) }
        }
    }
    private init(presenter: @escaping () -> UIViewController?) { self.presenter = presenter; super.init() }
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) { result(FlutterMethodNotImplemented) }
    private func fail(_ reply: FlutterResult, _ code: String, _ message: String) { reply(FlutterError(code: code, message: message, details: nil)) }
    private func unsupported(_ reply: FlutterResult) { fail(reply, "unsupported", "此功能在 iOS 上不可用或尚未配置入口") }
    private func top() -> UIViewController? {
        var v = presenter()
        while let p = v?.presentedViewController { v = p }
        return v
    }
    private func handle(_ channel: String, _ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch channel {
        case "install":
            switch call.method {
            case "lockEnabled": result(defaults.bool(forKey: "letian.app_lock"))
            case "setLock": defaults.set(args["off"] as? Bool != true, forKey: "letian.app_lock"); result(true)
            case "bioAuth":
                guard !authBusy else { fail(result, "busy", "正在验证"); return }
                let context = LAContext(); var error: NSError?
                guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { result(false); return }
                authBusy = true
                context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "请验证身份以解锁乐天助手") { ok, _ in
                    DispatchQueue.main.async { self.authBusy = false; result(ok) }
                }
            case "installFromUrl", "installApk": unsupported(result)
            default: result(FlutterMethodNotImplemented)
            }
        case "sys":
            switch call.method {
            case "openUrl":
                guard let s = args["url"] as? String, let url = LetianURLRules.external(s) else { fail(result, "open", "不支持的链接"); return }
                UIApplication.shared.open(url, options: [:]) { result($0) }
            case "openPrivateFile": openPrivate(args, result)
            case "openInstallSettings": unsupported(result)
            default: result(FlutterMethodNotImplemented)
            }
        case "camera":
            guard ["takePhoto", "pickPhoto"].contains(call.method) else { result(FlutterMethodNotImplemented); return }
            guard photoReply == nil, let host = top() else { fail(result, "busy", "请先完成当前照片选择"); return }
            photoReply = result
            if call.method == "pickPhoto" {
                var configuration = PHPickerConfiguration(); configuration.filter = .images; configuration.selectionLimit = 1
                let picker = PHPickerViewController(configuration: configuration); picker.delegate = self
                host.present(picker, animated: true); picker.presentationController?.delegate = self
            } else {
                guard UIImagePickerController.isSourceTypeAvailable(.camera) else { finishPhoto(nil, error: "此设备没有可用相机"); return }
                AVCaptureDevice.requestAccess(for: .video) { allowed in DispatchQueue.main.async {
                    guard allowed else { self.finishPhoto(nil, error: "相机权限未开启，请在系统设置中允许访问相机"); return }
                    guard let host = self.top() else { self.finishPhoto(nil, error: "无法打开相机"); return }
                    let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = self
                    host.present(picker, animated: true); picker.presentationController?.delegate = self
                } }
            }
        case "minis":
            let key = call.method == "download" ? "minis_download_url" : "minis_url"
            guard ["installed", "launch", "download"].contains(call.method) else { result(FlutterMethodNotImplemented); return }
            guard let raw = config[key] as? String, let c = LetianURLRules.web(raw), c.scheme == "https", let url = c.url else { unsupported(result); return }
            // A configured universal link is an entry point, not proof of an installed app.
            if call.method == "installed" { unsupported(result); return }
            UIApplication.shared.open(url, options: [:]) { result($0) }
        case "sync":
            switch call.method {
            case "pickTree":
                guard treeReply == nil, !syncBusy, let host = top() else { fail(result, "busy", "请先完成当前目录操作"); return }
                treeReply = result
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
                picker.delegate = self; picker.allowsMultipleSelection = false
                host.present(picker, animated: true); picker.presentationController?.delegate = self
            case "getTreeName": result(defaults.string(forKey: "letian.sync.name") ?? "")
            case "syncBackup": syncBackup(args, result)
            default: result(FlutterMethodNotImplemented)
            }
        default: result(FlutterMethodNotImplemented)
        }
    }
    private func finishPhoto(_ data: Data?, mime: String = "image/jpeg", error: String? = nil) {
        let reply = photoReply; photoReply = nil
        guard let reply = reply else { return }
        if let error = error { fail(reply, "camera", error) }
        else if let data = data {
            guard data.count <= photoLimit else { fail(reply, "camera", "图片超过 15 MB，请选择较小图片"); return }
            reply(["dataUrl": "data:\(mime);base64," + data.base64EncodedString()])
        } else { reply(nil) }
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true); finishPhoto(nil) }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { finishPhoto(nil, error: "未读取到图片"); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let data = image.jpegData(compressionQuality: 0.9)
            DispatchQueue.main.async { self.finishPhoto(data, error: data == nil ? "图片无法读取" : nil) }
        }
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let item = results.first?.itemProvider else { finishPhoto(nil); return }
        guard let type = item.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else { finishPhoto(nil, error: "图片格式不支持"); return }
        item.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
            do {
                guard let url = url else { throw CocoaError(.fileReadUnknown) }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= self.photoLimit else { DispatchQueue.main.async { self.finishPhoto(nil, error: "图片超过 15 MB，请选择较小图片") }; return }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: self.photoLimit + 1) ?? Data()
                DispatchQueue.main.async { self.finishPhoto(data, mime: UTType(type)?.preferredMIMEType ?? "image/jpeg") }
            } catch { DispatchQueue.main.async { self.finishPhoto(nil, error: "图片无法读取，请重试") } }
        }
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { treeReply?(nil); treeReply = nil }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let reply = treeReply; treeReply = nil
        guard let url = urls.first else { reply?(nil); return }
        guard url.startAccessingSecurityScopedResource() else { if let reply = reply { fail(reply, "directory", "无法访问所选目录，请重新授权") }; return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(data, forKey: "letian.sync.bookmark"); defaults.set(url.lastPathComponent, forKey: "letian.sync.name")
            reply?(["uri": url.absoluteString, "name": url.lastPathComponent])
        } catch { if let reply = reply { fail(reply, "directory", "无法保留目录授权，请重新选择") } }
    }
    private func trusted(_ value: String) -> URL? {
        guard let base = config["api_base_url"] as? String, LetianURLRules.sameOrigin(value, base) else { return nil }
        return URL(string: value)
    }
    private func openPrivate(_ args: [String: Any], _ result: @escaping FlutterResult) {
        guard !fileBusy else { fail(result, "busy", "请先完成当前文件操作"); return }
        guard let raw = args["url"] as? String, let url = trusted(raw), let token = args["token"] as? String, !token.isEmpty else { fail(result, "file", "文件地址或登录状态无效"); return }
        guard let host = top() else { fail(result, "file", "无法显示文件"); return }
        fileBusy = true; fileReply = result
        let operationID = UUID(); fileOperationID = operationID
        let alert = UIAlertController(title: "正在下载文件", message: "下载完成后可预览或分享。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            self.activeDownload?.cancel(); self.finishFile(false)
        })
        downloadAlert = alert; host.present(alert, animated: true)
        var request = URLRequest(url: url); request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let name = (args["name"] as? String ?? "download") as NSString
        let safeName = name.lastPathComponent
        activeDownload = session.downloadTask(with: request) { temporary, response, error in
            do {
                guard error == nil, let response = response as? HTTPURLResponse, response.statusCode == 200,
                      let temporary = temporary else { throw CocoaError(.fileReadUnknown) }
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("letian-native-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let target = directory.appendingPathComponent(safeName.isEmpty || safeName == "." || safeName == ".." ? "download" : safeName)
                do { try FileManager.default.moveItem(at: temporary, to: target) }
                catch { try? FileManager.default.removeItem(at: directory); throw error }
                DispatchQueue.main.async {
                    guard self.fileOperationID == operationID else { try? FileManager.default.removeItem(at: directory); return }
                    self.previewFile = target; self.activeDownload = nil
                    if let alert = self.downloadAlert {
                        self.downloadAlert = nil; alert.dismiss(animated: true) {
                            guard self.fileOperationID == operationID else { return }
                            self.showFile()
                        }
                    } else { self.showFile() }
                }
            } catch { DispatchQueue.main.async {
                guard self.fileOperationID == operationID else { return }
                self.finishFile(false, error: "文件下载失败，请重试")
            } }
        }
        activeDownload?.resume()
    }
    private func showFile() {
        guard let file = previewFile, let host = top() else { finishFile(false, error: "无法显示文件"); return }
        if QLPreviewController.canPreview(file as NSURL) {
            let preview = QLPreviewController(); preview.dataSource = self; preview.delegate = self; currentPreview = preview
            host.present(preview, animated: true); preview.presentationController?.delegate = self
        } else {
            let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = host.view
            share.popoverPresentationController?.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 1, height: 1)
            let operationID = fileOperationID
            share.completionWithItemsHandler = { _, complete, _, _ in
                guard self.fileOperationID == operationID else { return }
                self.finishFile(complete)
            }
            host.present(share, animated: true)
        }
    }
    private func finishFile(_ ok: Bool, error: String? = nil) {
        fileOperationID = nil; activeDownload = nil
        downloadAlert?.dismiss(animated: true); downloadAlert = nil
        if let file = previewFile { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        previewFile = nil; currentPreview = nil; fileBusy = false; let reply = fileReply; fileReply = nil
        if let reply = reply { if let error = error { fail(reply, "file", error) } else { reply(ok) } }
    }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewFile == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { (previewFile ?? FileManager.default.temporaryDirectory) as NSURL }
    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        guard currentPreview === controller else { return }; finishFile(true)
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if presentationController.presentedViewController is PHPickerViewController || presentationController.presentedViewController is UIImagePickerController { finishPhoto(nil) }
        else if presentationController.presentedViewController is UIDocumentPickerViewController { treeReply?(nil); treeReply = nil }
        else if let preview = presentationController.presentedViewController as? QLPreviewController, currentPreview === preview { finishFile(true) }
    }
    private func syncBackup(_ args: [String: Any], _ result: @escaping FlutterResult) {
        guard !syncBusy, treeReply == nil else { fail(result, "busy", "正在同步或选择目录"); return }
        guard let server = args["server"] as? String, let base = config["api_base_url"] as? String,
              trusted(server) != nil, let c = URLComponents(string: server), c.path.isEmpty || c.path == "/",
              c.query == nil, c.fragment == nil, let token = args["token"] as? String, !token.isEmpty else { fail(result, "sync", "同步地址或登录状态无效"); return }
        guard let bookmark = defaults.data(forKey: "letian.sync.bookmark") else { fail(result, "directory", "请先选择备份目录"); return }
        syncBusy = true
        DispatchQueue.global(qos: .utility).async {
            var uploaded = 0, failed = 0, skipped = 0
            do {
                var stale = false
                let folder = try URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
                guard folder.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
                defer { folder.stopAccessingSecurityScopedResource() }
                if stale {
                    let renewed = try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                    self.defaults.set(renewed, forKey: "letian.sync.bookmark")
                }
                let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
                for file in files {
                    if file.lastPathComponent.hasSuffix(".minisbak.enc") { skipped += 1; continue }
                    guard file.pathExtension == "minisbak" else { continue }
                    do {
                        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                        guard values.isRegularFile == true, values.isSymbolicLink != true else { failed += 1; continue }
                        var endpoint = URLComponents(string: base)!
                        endpoint.path = "/api/sync/upload"; endpoint.queryItems = [URLQueryItem(name: "name", value: file.lastPathComponent)]
                        var request = URLRequest(url: endpoint.url!); request.httpMethod = "POST"
                        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                        let wait = DispatchSemaphore(value: 0)
                        // No name-only deduplication: every account actually uploads its files.
                        var succeeded = false
                        self.session.uploadTask(with: request, fromFile: file) { _, response, error in
                            succeeded = error == nil && (200...299).contains((response as? HTTPURLResponse)?.statusCode ?? 0); wait.signal()
                        }.resume()
                        wait.wait()
                        if succeeded { uploaded += 1 } else { failed += 1 }
                    } catch { failed += 1 }
                }
                let summary = ["uploaded": uploaded, "failed": failed, "skippedEnc": skipped]
                DispatchQueue.main.async { self.syncBusy = false; result(summary) }
            } catch { DispatchQueue.main.async { self.syncBusy = false; self.fail(result, "directory", "无法读取备份目录，请重新授权") } }
        }
    }
}
