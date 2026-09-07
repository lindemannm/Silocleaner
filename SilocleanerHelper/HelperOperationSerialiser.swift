import Foundation

/// Keeps privileged mutations strictly ordered even when several XPC clients
/// submit requests at once.  This is deliberately separate from the listener
/// so its serialization guarantee can be exercised without a root service.
final class HelperOperationSerialiser {
    private let queue = DispatchQueue(label: "com.lindemannm.Silocleaner.helper.operations")

    func execute(_ operation: @escaping @Sendable () -> Void) {
        queue.async(execute: operation)
    }
}
