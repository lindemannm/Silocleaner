//
//  main.swift
//  SilocleanerHelper
//
//  Created by Alin Lupascu on 3/14/25.
//

import Foundation
import ObjectiveC
import os

@objc(HelperToolProtocol)
public protocol HelperToolProtocol {
    func thinApplicationBundle(_ request: HelperBundleThinningRequest, withReply reply: @escaping (HelperBundleThinningResult) -> Void)
}

@objc(SilocleanerBundleThinningRequest)
public final class HelperBundleThinningRequest: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }
    let bundlePath: String

    init(bundlePath: String) { self.bundlePath = bundlePath }
    public required init?(coder: NSCoder) {
        guard let path = coder.decodeObject(of: NSString.self, forKey: "bundlePath") as String? else { return nil }
        bundlePath = path
    }
    public func encode(with coder: NSCoder) { coder.encode(bundlePath as NSString, forKey: "bundlePath") }
}

@objc(SilocleanerBundleThinningResult)
public final class HelperBundleThinningResult: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }
    let succeeded: Bool
    let preSize: UInt64
    let postSize: UInt64

    init(succeeded: Bool, preSize: UInt64 = 0, postSize: UInt64 = 0) {
        self.succeeded = succeeded; self.preSize = preSize; self.postSize = postSize
    }
    public required init?(coder: NSCoder) {
        succeeded = coder.decodeBool(forKey: "succeeded")
        preSize = UInt64(coder.decodeInt64(forKey: "preSize"))
        postSize = UInt64(coder.decodeInt64(forKey: "postSize"))
    }
    public func encode(with coder: NSCoder) {
        coder.encode(succeeded, forKey: "succeeded")
        coder.encode(Int64(clamping: preSize), forKey: "preSize")
        coder.encode(Int64(clamping: postSize), forKey: "postSize")
    }
}

// XPC Communication setup
class HelperToolDelegate: NSObject, NSXPCListenerDelegate, HelperToolProtocol {
    private var activeConnections = Set<NSXPCConnection>()
    private let connectionLock = NSLock()
    private let operationQueue = DispatchQueue(label: "com.lindemannm.Silocleaner.helper.operations")
    private let logger = Logger(subsystem: "com.lindemannm.Silocleaner", category: "privileged-helper")

    
    // Accept new XPC connections by setting up the exported interface and object.
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard isValidClient(connection: newConnection) else {
            logger.error("Rejected unauthorized helper client")
            return false
        }
        newConnection.exportedInterface = NSXPCInterface(with: HelperToolProtocol.self)
        newConnection.exportedInterface?.setClasses(xpcClasses(HelperBundleThinningRequest.self), for: #selector(thinApplicationBundle(_:withReply:)), argumentIndex: 0, ofReply: false)
        newConnection.exportedInterface?.setClasses(xpcClasses(HelperBundleThinningResult.self), for: #selector(thinApplicationBundle(_:withReply:)), argumentIndex: 0, ofReply: true)
        newConnection.exportedObject = self
        newConnection.invalidationHandler = { [weak self] in
            self?.connectionLock.lock()
            self?.activeConnections.remove(newConnection)
            self?.connectionLock.unlock()
            self?.logger.info("Helper client connection invalidated")
        }
        connectionLock.lock()
        activeConnections.insert(newConnection)
        connectionLock.unlock()
        newConnection.resume()
        return true
    }

    func thinApplicationBundle(_ request: HelperBundleThinningRequest, withReply reply: @escaping (HelperBundleThinningResult) -> Void) {
        operationQueue.async { [logger] in
            let result = PrivilegedBundleThinner.thin(bundlePath: request.bundlePath)
            logger.info("Completed privileged bundle-thinning request: success=\(result.succeeded, privacy: .public)")
            reply(HelperBundleThinningResult(succeeded: result.succeeded, preSize: result.preSize, postSize: result.postSize))
        }
    }

    // Only the exact, Developer-ID-signed main app may use this root service.
    private func isValidClient(connection: NSXPCConnection) -> Bool {
        do {
            return try CodesignCheck.isAuthorizedClient(pid: connection.processIdentifier)
        } catch {
            logger.error("Helper code-signing validation failed")
            return false
        }
    }
}

private func xpcClasses(_ type: AnyClass) -> Set<AnyHashable> {
    NSSet(object: type) as! Set<AnyHashable>
}

// Set up and start the XPC listener.
let delegate = HelperToolDelegate()
let listener = NSXPCListener(machServiceName: "com.lindemannm.Silocleaner.SilocleanerHelper")
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
