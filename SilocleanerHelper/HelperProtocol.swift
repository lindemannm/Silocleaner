import Foundation

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
