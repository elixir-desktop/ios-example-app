import Foundation
import Network
import ZIPFoundation
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

class Notification {
    var title: String = ""
    var message: String = ""
    var callback: String = ""
    var pid: Any = 0
    var obj: [Any] = []
}

class Bridge {
    var webview: WebViewController?
    var listener: NWListener?
    let home: URL
    var lastURL: URL?
    static public var instance: Bridge?
    var erlangStarted = false
    var listenerStarted = 0
    
    var notifications: Dictionary<Int, Notification> = [:]
    let globalQueue = DispatchQueue.global()
    
    static public var isActiveState: Bool = false
    
    func setWebView(view :WebViewController) {
        self.webview = view
        self.webview?.webview.bridge = self
        loadURL()
    }
    
    func setURL(url :String) {
        lastURL = URL(string: url)
        loadURL()
    }
    
    func loadURL() {
        if let view = self.webview {
            if let url = self.lastURL {
                print ("opening \(url)")
                view.loadURL(url: url)
            }
        }
    }

    func getNotification(id: Int) -> Notification? {
        var notification = self.notifications[id]
        if (notification != nil) {
            return notification
        } else {
            notification = Notification()
            notifications[id] = notification
            return notification
        }
    }
    
    func json(from object:Any) -> String? {
        debug("json(\(object))")
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
            return nil
        }
        return String(data: data, encoding: String.Encoding.utf8)
    }
    
    func sendMessage(prefix: [UInt32], json: String) {
        var n = 1;
        while self.connectionsByID.count == 0 {
            debug("Waiting for connections \(n)")
            n = n + 1
            usleep(1000000)
        }
        
        for connection in self.connectionsByID.values {
            let payload = (connection.listToString(raw: prefix) + json)
            let data = payload.data(using: .utf8)!

            let size: UInt32 = CFSwapInt32(UInt32(data.count))
            var message = withUnsafeBytes(of: size) { Data($0) }

            message.append(data)
            connection.send(data: message)
            break
        }
    }
    
    func stringToList(string: String) -> [UInt8] {
        let data = string.data(using: .utf8)!
        let numbers = data.map { $0 * 1 }
        return numbers
    }

    func stringToListString(string: String) -> String {
        return "[" + stringToList(string: string).map { String($0) }.joined(separator: ",") + "]"
    }
    
    func clickNotification(id: Int) {
        let notification = self.getNotification(id: id)
        let encodedNotification = self.json(from: notification!.pid)
        let encodedObject = self.json(from: notification!.obj)

        let event = """
            {":_type": ":tuple", ":value": [
                ":wxCommand", ":notification_message_click", "", 0, 0
            ]}
        """.trimmingCharacters(in: .whitespacesAndNewlines)
        let json = """
            {":pid": \(encodedNotification!), ":payload":
                {":_type": ":tuple", ":value": [":wx", \(id), \(encodedObject!), [], \(event)]}
            }
        """.trimmingCharacters(in: .whitespacesAndNewlines)
        var prefix = [UInt32](repeating: 0, count: 8)
        prefix[7] = 2

        globalQueue.async {
            self.sendMessage(prefix: prefix, json: json)
        }
    }

    private var connectionsByID: [Int: ServerConnection] = [:]

    init() throws {
        debug("bridge init()")
        home = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent(Bundle.main.bundleIdentifier!)
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        
        // Extracting the app
        let infoAttr = try FileManager.default.attributesOfItem(atPath: zipFile().path)
        let infoDate = infoAttr[FileAttributeKey.creationDate] as! Date
        let build = UserDefaults.standard.string(forKey: "app_build_date")
        
        debug("Preparing app files \(infoDate.description) installed: \(String(describing: build))")

        let appdir = home.appendingPathComponent("app")
        let info = appdir.appendingPathComponent("releases").appendingPathComponent("start_erl.data")
        
        if (!FileManager.default.fileExists(atPath: info.path)) {
            debug("Default app not found, downloading new one...")
            try unzipApp(dest: appdir)
        } else if (infoDate.description != build){
            debug("InfoDate description != build date, downloading new one...")
            try FileManager.default.removeItem(atPath: appdir.path)
            try unzipApp(dest: appdir)
            UserDefaults.standard.set(infoDate.description, forKey: "app_build_date")
        }
        
        let inet_rc = appdir.appendingPathComponent("inetrc")
        setEnv(name: "ERL_INETRC", value: inet_rc.path)
        //if (!FileManager.default.fileExists(atPath: inet_rc.path)) {
            let rc = #"""
            %% enable EDNS, 0 means enable YES!
            {edns,0}.
            {alt_nameserver, {8,8,8,8}}.
            %% specify lookup method
            {lookup, [dns]}.
            """#
            debug("'\(rc)'")
            try! rc.write(to: inet_rc, atomically: true, encoding: .utf8)
        //}

        setupListener()
        Bridge.instance = self
        debug("Server starting...")
    }
    
    private func debug(_ str: String) {
        print(str)
        /*if let wvc = self.webview {
            DispatchQueue.global(qos: .userInitiated).async {
                wvc.webview.webview.loadHTMLString(str, baseURL: nil)
            }
        }*/
    }
    
    func setupListener() {
        debug("Starting listener on \(Bridge.port())...")
        let l = try! NWListener(using: .tcp, on: Bridge.port())
        l.stateUpdateHandler = self.stateDidChange(to:)
        l.newConnectionHandler = self.didAccept(nwConnection:)
        l.start(queue: .global())
        listener = l
    }
    
    func reinit() {
        listenerStarted = listenerStarted + 1
        debug("Server re-init called: \(self.listenerStarted)")
        if listenerStarted <= 1 {
            return
        }
        let conn = connectionsByID.first
        if conn == nil ||
            conn?.value.connection.state == .cancelled {
            stopListener()
            setupListener()
        }
    }

    static func port() -> NWEndpoint.Port {
        return NWEndpoint.Port("23115")!
    }
    
    func setEnv(name: String, value: String) {
        debug("setenv \(name) \(value)")
        setenv(name, value, 1)
    }
    
    func zipFile() -> URL {
        return Bundle.main.url(forResource: "app", withExtension: "zip")!
    }
    
    func unzipApp(dest: URL) throws {
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.unzipItem(at: zipFile(), to: dest)
    }

    func stateDidChange(to newState: NWListener.State) {
        switch newState {
        case .ready:
            if erlangStarted {
                break
            }
            erlangStarted = true
            debug("Bridge Server ready. Starting Elixir")
            setEnv(name: "ELIXIR_DESKTOP_OS", value: "ios")
            setEnv(name: "BRIDGE_PORT", value: (listener?.port?.rawValue.description)!)
            // not really the home directory, but persistent between app upgrades (yes?)
            setEnv(name: "HOME", value: home.path)
            // BINDIR is not used on iOS but needs to be defined
            let bindir = home.appendingPathComponent("bin")
            setEnv(name: "BINDIR", value: bindir.path)
            
            let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            let logdir = urls[0].path
            let appdir = home.appendingPathComponent("app")
            let ret = start_erlang(appdir.path, logdir)
            debug("Ret: " + String(cString: ret!))

        case .failed(let error):
            debug("Server failure, error: \(error.localizedDescription)")
            exit(EXIT_FAILURE)
        case .cancelled:
            debug("Server failure, cancelled")
            exit(EXIT_FAILURE)
        default:
            debug("Server unknown new state: \(newState)")
            break
        }
    }
    
    private func didAccept(nwConnection: NWConnection) {
        let connection = ServerConnection(nwConnection: nwConnection, bridge: self)
        self.connectionsByID[connection.id] = connection
        connection.didStopCallback = { _ in
            self.connectionDidStop(connection)
        }
        connection.start()
        let payload = "\0\0\0\0\0\0\0\0\":reconnect\"".data(using: .utf8)!
        let size: UInt32 = CFSwapInt32(UInt32(payload.count))
        var message = withUnsafeBytes(of: size) { Data($0) }
        message.append(payload)
        connection.send(data: message)

        // connection.send(data: "Welcome you are connection: \(connection.id)".data(using: .utf8)!)
        debug("server did open connection \(connection.id)")
    }
    
    private func connectionDidStop(_ connection: ServerConnection) {
        self.connectionsByID.removeValue(forKey: connection.id)
        debug("server did close connection \(connection.id)")
    }
    
    private func stopListener() {
        if let l = listener {
            l.stateUpdateHandler = nil
            l.newConnectionHandler = nil
            l.cancel()
        }
    }

    private func stop() {
        debug("stop() called")

        stopListener()
        for connection in self.connectionsByID.values {
            connection.didStopCallback = nil
            connection.stop()
        }
        self.connectionsByID.removeAll()
    }
        
    func publishEvent(eventType: String, eventData: String) {
        let json = """
            {":_type": ":tuple", ":value": [":\(eventType)", [\(eventData)]]}
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        let prefix = [UInt32](repeating: 0, count: 8)
        self.sendMessage(prefix: prefix, json: json)
    }

    func publishFiles(filenames: [URL]) {
        let namesString = filenames.map{ self.stringToListString(string: $0.absoluteString) }
        publishEvent(eventType: "open_file", eventData: namesString.joined(separator: ","))
    }

    static func updateActiveState(_ active: Bool) {
        isActiveState = active
    }
}

class ServerConnection {
    //The TCP maximum package size is 64K 65536
    let MTU = 65536

    private static var nextID: Int = 0
    let connection: NWConnection
    let id: Int
    var bridge: Bridge

    init(nwConnection: NWConnection, bridge: Bridge) {
        self.bridge = bridge
        connection = nwConnection
        id = ServerConnection.nextID
        ServerConnection.nextID += 1
    }

    var didStopCallback: ((Error?) -> Void)? = nil

    func start() {
        connection.stateUpdateHandler = self.stateDidChange(to:)
        setupReceive()
        connection.start(queue: .main)
    }

    private func stateDidChange(to state: NWConnection.State) {
        switch state {
        case .waiting(let error):
            connectionDidFail(error: error)
        case .failed(let error):
            connectionDidFail(error: error)
        case .ready:
            break
        default:
            break
        }
    }

    private func setupReceive() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { (data, _, isComplete, error) in
            if isComplete {
                self.connectionDidEnd()
                return
            }
            
            if let error = error {
                self.connectionDidFail(error: error)
                return
            }
            
            let length: Int = Int(CFSwapInt32(data!.uint32))
            self.connection.receive(minimumIncompleteLength: length, maximumLength: length) { (datain, _, isComplete, error) in
                if isComplete {
                    self.connectionDidEnd()
                    return
                }
                
                if let error = error {
                    self.connectionDidFail(error: error)
                    return
                }
                
                let ref = datain!.prefix(8)
                let data = datain!.dropFirst(8)
                let json = try! JSONSerialization.jsonObject(with: data, options: [])
                
                let array = json as! [Any]
                let module = array[0] as? String
                let method = array[1] as? String
                let args = array[2] as? [Any]
                
                if (module == ":wxNotificationMessage") {
                    self.processNotification(method: method, args: args)
                }
                
                //print ("received \(method)")
                if (method == ":loadURL") {
                    self.bridge.setURL(url: args![1] as! String)
                }
                if (method == ":launchDefaultBrowser") {
                    let originalUrl = args![0] as! String
                    
                    if originalUrl.starts(with: "https://") {
                        let url = URL(string: originalUrl)
                        UIApplication.shared.open(url!)
                    } else if originalUrl.starts(with: "file://") {
                        if let url = URL(string: originalUrl) {
                            // Create a temporary directory URL
                            let tempDirURL = FileManager.default.temporaryDirectory
                            let fileName = url.lastPathComponent
                            let tempFileURL = tempDirURL.appendingPathComponent(fileName)
                            
                            do {
                                // If a previous temp file exists, remove it
                                if FileManager.default.fileExists(atPath: tempFileURL.path) {
                                    try FileManager.default.removeItem(at: tempFileURL)
                                }
                                
                                // Copy the file to temporary location
                                try FileManager.default.copyItem(at: url, to: tempFileURL)
                                
                                // Share the temporary file
                                var activityItems: [Any] = []
                                
                                // Try to create appropriate sharing item based on file type
                                if let fileType = UTType(filenameExtension: url.pathExtension) {
                                    if fileType.conforms(to: .image) {
                                        if let image = UIImage(contentsOfFile: tempFileURL.path) {
                                            activityItems.append(image)
                                        }
                                    } else if fileType.conforms(to: .movie) {
                                        let video = AVAsset(url: tempFileURL)
                                        activityItems.append(video)
                                    } else if fileType.conforms(to: .pdf) {
                                        if let pdf = try? Data(contentsOf: tempFileURL) {
                                            activityItems.append(pdf)
                                        }
                                    }
                                }
                                
                                // Always add the file URL as fallback
                                activityItems.append(tempFileURL)
                                
                                let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
                                
                                // Add additional metadata
                                activityVC.completionWithItemsHandler = { (activityType, completed, returnedItems, error) in
                                    // Clean up temp file after sharing
                                    try? FileManager.default.removeItem(at: tempFileURL)
                                }
                                
                                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                   let rootViewController = windowScene.windows.first?.rootViewController {
                                    rootViewController.present(activityVC, animated: true)
                                }
                            } catch {
                                Bridge.sdebug("Error preparing file for sharing: \(error.localizedDescription)")
                            }
                        }
                    }
                }

                var response = ref
                if (method == ":getOsDescription") {
                    response.append(self.dataToList(string: "iOS \(UIDevice().model)"))
                } else if (method == ":getCanonicalName") {
                    // Fetch current local and return in format "en_en"
                    // let locale = Locale.current.identifier
                    // Only the first 5 characters:
                    // let canonical = locale.isEmpty ? "en_en" : locale.prefix(5).lowercased()
                    let canonical = Locale.preferredLanguages.joined(separator: "|").lowercased().replacingOccurrences(of: "-", with: "_")
                    response.append(self.dataToList(string: canonical))
                } else if (method == ":isActive") {
                    response.append((Bridge.isActiveState ? "true" : "false").data(using: .utf8)!)
                } else {
                    response.append("use_mock".data(using: .utf8)!)
                }
                
                let size: UInt32 = CFSwapInt32(UInt32(response.count))
                var message = withUnsafeBytes(of: size) { Data($0) }
                message.append(response)
                self.send(data: message)
                //self.send(data: response)
                self.setupReceive()
            }
        }
    }
    
    func getValueByKey(keywords: [Any], searchKey : String) -> Any {
        for keyword in keywords {
            let parsedDictionary = keyword as! [String: Any]
            let tupleValues = parsedDictionary[":value"] as! [Any]
            let key = tupleValues[0] as! String
            if (key == searchKey) {
                return tupleValues[1]
            }
        }
        return ""
    }
    
    func listToString(raw : [Any]) -> String {
        var title = ""
        for i in raw {
            let letter = UnicodeScalar(i as! UInt32)
            title = title + String(letter!)
        }
        return title
    }
    
    func processNotification(method : String?, args: [Any]?) {
        let obj = args![0] as! [Any]

        if let id = self.getValueByKey(keywords: obj, searchKey: ":id") as? Int {

            let notification = self.bridge.getNotification(id: id)!
            notification.obj = obj

            if method == ":setTitle" {
                Bridge.sdebug("NOTIFICATION: setTitle()")
                notification.title = self.listToString(raw: args![1] as! [Any])
                return
            }

            if method == ":setMessage" {
                Bridge.sdebug("NOTIFICATION", "setMessage()")
                notification.message = self.listToString(raw: args![1] as! [Any])
                return
            }

            if method == ":connect" {
                Bridge.sdebug("NOTIFICATION", "connect()")
                notification.pid = args![(args!.count - 1)]
                return
            }

            if method == ":show" {
                Bridge.sdebug("NOTIFICATION", "show()")
                self.sendNotification(id: id, notification: notification)
                return
            }
        }
    }
    
    func sendNotification(id: Int, notification: Notification) {
        let notificationContent = UNMutableNotificationContent()
        let userNotificationCenter = UNUserNotificationCenter.current()

        notificationContent.title = notification.title
        notificationContent.body = notification.message
        notificationContent.userInfo = ["wxid": id]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5,
                                                        repeats: false)
        let request = UNNotificationRequest(identifier: String(id),
                                            content: notificationContent,
                                            trigger: trigger)

        userNotificationCenter.add(request) { (error) in
            if let error = error {
                Bridge.sdebug("Notification Error: ", error)
            }
        }
    }
    
    func dataToList(string: String) -> Data {
        return dataToList(data: string.data(using: .utf8)!)
    }
    func dataToList(data: Data) -> Data {
        let numbers = data.map { "\($0)" }
        return "[\(numbers.joined(separator: ","))]".data(using: .utf8)!
    }
    
    func send(data: Data) {
        self.connection.send(content: data, completion: .contentProcessed( { error in
            if let error = error {
                self.connectionDidFail(error: error)
                return
            }
        }))
    }

    func stop() {
        debug("connection \(id) will stop")
    }

    private func connectionDidFail(error: Error) {
        debug("connection \(id) did fail, error: \(error)")
        stop(error: error)
    }

    private func connectionDidEnd() {
        debug("connection \(id) did end")
        stop(error: nil)
    }

    private func stop(error: Error?) {
        connection.stateUpdateHandler = nil
        connection.cancel()
        if let didStopCallback = didStopCallback {
            self.didStopCallback = nil
            didStopCallback(error)
        }
    }
}

extension Data {
    var uint32: UInt32 {
        get {
            let i32array = self.withUnsafeBytes { $0.load(as: UInt32.self) }
            return i32array
        }
    }
}
