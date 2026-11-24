import Foundation
import UIKit
import AVFoundation
import AuthenticationServices
import Capacitor

// マイ英語の iOS 専用の部品。（読み上げの知らせは、いつもメインスレッドで処理する）
//Webページ（index.html）から MyEigoNative という名前で呼ばれる。
//  - speak    : 文のならび（キュー）を、iPhone の声で順番に読み上げる。画面を消しても、ほかのアプリを開いても続く
//  - stop     : 読み上げを止める
//  - getVoices: iPhone に入っている声の一覧
//  - authenticate : Google のログイン画面（Safari の安全な画面）を開いて、もどってきた URL を返す
//  - httpPost : ログインのあとの「通行証」の受け取りなど、Webページからは送れない通信
//  - keepAwake: 画面が自動で消えないようにする
//  - shareFile: バックアップのファイルを「共有」で、ファイルAppに保存したり、AirDrop で送ったりする
@objc(MyEigoNativePlugin)
public class MyEigoNativePlugin: CAPPlugin, CAPBridgedPlugin, AVSpeechSynthesizerDelegate, ASWebAuthenticationPresentationContextProviding {
    public let identifier = "MyEigoNativePlugin"
    public let jsName = "MyEigoNative"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "speak", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getVoices", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "authenticate", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "httpPost", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "keepAwake", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "shareFile", returnType: CAPPluginReturnPromise)
    ]

    private let synth = AVSpeechSynthesizer()
    private var runId = 0                                   // いま有効な speak() の番号（古い読み上げの知らせは無視する）
    private var runCount = 0                                // その speak() の文の数
    private var pending: [ObjectIdentifier: (Int, Int)] = [:] // 読み上げ中の文 → (speak の番号, 何番目の文か)
    private var authSession: ASWebAuthenticationSession?

    @objc override public func load() {
        synth.delegate = self
    }

    // MARK: - 読み上げ

    private func number(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return nil
    }

    private func activateAudio() {
        // 「再生」用の音として使う → 消音スイッチがオンでも鳴り、画面を消しても続く（Info.plist の audio と組み合わせる）
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    @objc func speak(_ call: CAPPluginCall) {
        guard let items = call.getArray("items") else {
            call.reject("items is required")
            return
        }
        DispatchQueue.main.async {
            self.activateAudio()
            self.runId += 1
            let run = self.runId
            self.pending.removeAll()
            if self.synth.isSpeaking || self.synth.isPaused {
                self.synth.stopSpeaking(at: .immediate)
            }
            var count = 0
            for raw in items {
                guard let item = raw as? JSObject else { continue }
                let text = (item["text"] as? String) ?? ""
                let utterance = AVSpeechUtterance(string: text.isEmpty ? " " : text)
                let lang = (item["lang"] as? String) ?? "en-US"
                if let id = item["voice"] as? String, !id.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: id) {
                    utterance.voice = voice
                } else {
                    utterance.voice = AVSpeechSynthesisVoice(language: lang)
                }
                // Webの速さ（1.0 がふつう）→ iPhone の速さ（0.5 がふつう）
                let rate = self.number(item["rate"]) ?? 1.0
                utterance.rate = Float(min(max(rate * Double(AVSpeechUtteranceDefaultSpeechRate), 0.1), 0.75))
                utterance.preUtteranceDelay = (self.number(item["pre"]) ?? 0) / 1000.0
                utterance.postUtteranceDelay = (self.number(item["post"]) ?? 0) / 1000.0
                self.pending[ObjectIdentifier(utterance)] = (run, count)
                count += 1
                self.synth.speak(utterance)
            }
            self.runCount = count
            call.resolve(["run": run])
        }
    }

    @objc func stop(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.runId += 1
            self.pending.removeAll()
            self.synth.stopSpeaking(at: .immediate)
            call.resolve()
        }
    }

    @objc func getVoices(_ call: CAPPluginCall) {
        let list: [[String: Any]] = AVSpeechSynthesisVoice.speechVoices().map { v in
            ["id": v.identifier, "name": v.name, "lang": v.language, "quality": v.quality.rawValue]
        }
        call.resolve(["voices": list])
    }

    private func send(_ type: String, _ utterance: AVSpeechUtterance, _ extra: [String: Any] = [:]) {
        guard let entry = pending[ObjectIdentifier(utterance)], entry.0 == runId else { return }
        let run = entry.0, index = entry.1
        var data: [String: Any] = ["type": type, "run": run, "index": index]
        for (k, v) in extra { data[k] = v }
        notifyListeners("speech", data: data)
        if type == "end" {
            pending.removeValue(forKey: ObjectIdentifier(utterance))
            if index == runCount - 1 {
                notifyListeners("speech", data: ["type": "done", "run": run, "index": index])
            }
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.send("start", utterance) }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let loc = characterRange.location, len = characterRange.length
        DispatchQueue.main.async { self.send("boundary", utterance, ["charIndex": loc, "charLength": len]) }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.send("end", utterance) }
    }

    // MARK: - Google ログイン

    @objc func authenticate(_ call: CAPPluginCall) {
        guard let urlString = call.getString("url"), let url = URL(string: urlString), let scheme = call.getString("scheme") else {
            call.reject("url and scheme are required")
            return
        }
        DispatchQueue.main.async {
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
                self.authSession = nil
                if let callbackURL = callbackURL {
                    call.resolve(["url": callbackURL.absoluteString])
                } else {
                    let canceled = (error as NSError?)?.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
                    call.reject(canceled ? "ログインが中止されました" : (error?.localizedDescription ?? "ログインできませんでした"), canceled ? "CANCELED" : "ERROR")
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false   // 一度ログインしたら、次はすぐ終わるように
            self.authSession = session
            if !session.start() {
                self.authSession = nil
                call.reject("ログイン画面を開けませんでした")
            }
        }
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return bridge?.viewController?.view.window ?? ASPresentationAnchor()
    }

    // MARK: - 通信

    @objc func httpPost(_ call: CAPPluginCall) {
        guard let urlString = call.getString("url"), let url = URL(string: urlString) else {
            call.reject("url is required")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(call.getString("contentType") ?? "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = (call.getString("body") ?? "").data(using: .utf8)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                call.reject(error.localizedDescription)
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            call.resolve(["status": status, "data": String(data: data ?? Data(), encoding: .utf8) ?? ""])
        }.resume()
    }

    // MARK: - 画面を消さない

    @objc func keepAwake(_ call: CAPPluginCall) {
        let on = call.getBool("on") ?? false
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = on
            call.resolve()
        }
    }

    // MARK: - ファイルを共有（バックアップの保存）

    @objc func shareFile(_ call: CAPPluginCall) {
        let name = call.getString("name") ?? "backup.json"
        let text = call.getString("text") ?? ""
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            call.reject("ファイルを作れませんでした")
            return
        }
        DispatchQueue.main.async {
            guard let vc = self.bridge?.viewController else {
                call.reject("画面がありません")
                return
            }
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = vc.view
            sheet.completionWithItemsHandler = { _, completed, _, _ in
                call.resolve(["completed": completed])
            }
            vc.present(sheet, animated: true)
        }
    }
}
