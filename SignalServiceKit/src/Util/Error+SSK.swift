//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

extension NSError {
    // Only StatusCodeForError() should use this method.
    // It only works for AFNetworking errors.
    // Use StatusCodeForError() instead.
    @objc
    public func afHttpStatusCode() -> NSNumber? {
        guard domain == AFURLResponseSerializationErrorDomain else {
            return nil
        }
        guard let response = userInfo[AFNetworkingOperationFailingURLResponseErrorKey] as? HTTPURLResponse else {
            return nil
        }
        return NSNumber(value: response.statusCode)
    }

    @objc
    public func hasFatalAFStatusCode() -> Bool {
        guard let statusCode = afHttpStatusCode()?.intValue else {
            return false
        }
        if statusCode == 429 {
            // "Too Many Requests", retry with backoff.
            return false
        }
        return 400 <= statusCode && statusCode <= 499
    }
}

// MARK: -

public protocol OperationError: CustomNSError {
    var isRetryable: Bool { get }
}

// MARK: -

public extension OperationError {
    var errorUserInfo: [String: Any] {
        return [OWSOperationIsRetryableKey: self.isRetryable]
    }
}

extension NSError: OperationError { }

extension OWSAssertionError: OperationError {
    public var isRetryable: Bool {
        return false
    }
}

/// Swift/ObjC error bridging is a little tricky.
///
/// Our NSError objects have an associatedObject backing `NSError.isRetryable`, but our Swift errors do not inherit that.
///
/// It's tempting to think we can do something like:
///
///    enum MyError: Error {
///        case .foo
///    }
///    assert((foo as NSError).isRetryable == false)
///   (foo as NSError).isRetryable = true // <-- Doesn't do what you think it does!
///   operation.reportError(foo)
///    assert((foo as NSError).isRetryable == false) // <-- STILL false!
///
///  In the above case, `foo` remains untouched because `(foo as NSError)` creates a new instance of NSError, so when we're setting
/// `isRetryable`, it's on that new instance, while foo remains untouched.
///
/// On the other hand, this works:
///
///    let nsError = foo as NSError
///    nsError.isRetryable = true
///    reportError(nsError)
///
/// But better yet, is to prefer reporting instances that conform to OperationError.
extension OWSOperation {
    /// The preferred error reporting mechanism, ensuring retry behavior has
    /// been specified. If your error has overridden errorUserInfo, be sure it
    /// includes an entry for OWSOperationIsRetryableKey.
    public func reportError(_ error: OperationError) {
        __reportError(error)
    }

    /// Use this if you've verified the error passed in has in fact defined retry behavior, or if you're
    /// comfortable potentially falling back to the default retry behavior (see `NSError.isRetryable`).
    ///
    /// @param `error` may or may not have defined it's retry behavior.
    public func reportError(withUndefinedRetry error: Error) {
        __reportError(error)
    }
}
