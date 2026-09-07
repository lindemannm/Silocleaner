//
//  main.swift
//  SilocleanerHelper
//
//  Created by Alin Lupascu on 3/14/25.
//

import Foundation
import os

// XPC Communication setup
class HelperToolDelegate: NSObject, NSXPCListenerDelegate, HelperToolProtocol {
    private var activeConnections = Set<NSXPCConnection>()
    private let connectionLock = NSLock()
    private let operationSerialiser = HelperOperationSerialiser()
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
        operationSerialiser.execute { [logger] in
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
