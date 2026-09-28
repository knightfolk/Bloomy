import AppKit
import DarkbloomCompanionHost
import DarkbloomCompanionProtocol
import Foundation
import Security

public enum RegisteredAppError: Error, Equatable, Sendable {
    case invalidRegistration
    case identityMismatch
    case dirtyDraft
    case multipleInstances
    case quitRefused
}

public struct RegisteredAppIdentity: Sendable {
    public let bundleIdentifier: String
    public let bundleURL: URL
    public let designatedRequirement: String

    /// Values come from the installed signed app's registration, never from a
    /// remote command. A caller can request only an enum lifecycle action.
    public init(bundleIdentifier: String, bundleURL: URL, designatedRequirement: String) throws {
        guard !bundleIdentifier.isEmpty, !designatedRequirement.isEmpty,
              bundleURL.isFileURL, bundleURL.pathExtension == "app" else {
            throw RegisteredAppError.invalidRegistration
        }
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        self.designatedRequirement = designatedRequirement
    }
}

public struct RegisteredRunningApp: Sendable {
    public let processID: Int32
    public let bundleURL: URL?

    public init(processID: Int32, bundleURL: URL?) {
        self.processID = processID
        self.bundleURL = bundleURL
    }
}

public protocol RegisteredAppSystem: Sendable {
    func bundleIdentifier(at url: URL) async -> String?
    func signatureMatches(at url: URL, requirement: String) async -> Bool
    func signatureMatchesRunning(processID: Int32, requirement: String) async -> Bool
    func runningApps(bundleIdentifier: String) async -> [RegisteredRunningApp]
    func open(_ url: URL) async throws
    func terminate(processID: Int32) async -> Bool
    func isRunning(processID: Int32) async -> Bool
}

public actor RegisteredAppLifecycleDispatcher: MacAppLifecycleControlling {
    private let registration: RegisteredAppIdentity
    private let system: any RegisteredAppSystem
    private let canQuit: @Sendable () async -> Bool

    public init(
        registration: RegisteredAppIdentity,
        system: any RegisteredAppSystem,
        canQuit: @escaping @Sendable () async -> Bool
    ) {
        self.registration = registration
        self.system = system
        self.canQuit = canQuit
    }

    public func perform(_ action: AppLifecycleAction) async throws {
        switch action {
        case .open: try await open()
        case .quit: try await quit()
        case .relaunch:
            try await quit()
            try await open()
        }
    }

    private func verify(_ url: URL) async throws {
        guard url.standardizedFileURL.resolvingSymlinksInPath() == registration.bundleURL,
              await system.bundleIdentifier(at: url) == registration.bundleIdentifier,
              await system.signatureMatches(at: url, requirement: registration.designatedRequirement)
        else { throw RegisteredAppError.identityMismatch }
    }

    private func open() async throws {
        try await verify(registration.bundleURL)
        try await system.open(registration.bundleURL)
    }

    private func quit() async throws {
        guard await canQuit() else { throw RegisteredAppError.dirtyDraft }
        let running = await system.runningApps(bundleIdentifier: registration.bundleIdentifier)
        guard running.count <= 1 else { throw RegisteredAppError.multipleInstances }
        guard let app = running.first else { return }
        guard let url = app.bundleURL else { throw RegisteredAppError.identityMismatch }
        try await verify(url)
        guard await system.signatureMatchesRunning(
            processID: app.processID, requirement: registration.designatedRequirement
        ) else { throw RegisteredAppError.identityMismatch }
        guard await system.terminate(processID: app.processID) else { throw RegisteredAppError.quitRefused }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while await system.isRunning(processID: app.processID), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard await !system.isRunning(processID: app.processID) else { throw RegisteredAppError.quitRefused }
    }
}

public actor MacRegisteredAppSystem: RegisteredAppSystem {
    public init() {}

    public func bundleIdentifier(at url: URL) -> String? { Bundle(url: url)?.bundleIdentifier }

    public func signatureMatches(at url: URL, requirement: String) -> Bool {
        var code: SecStaticCode?
        var requirementObject: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code) == errSecSuccess,
              SecRequirementCreateWithString(requirement as CFString, SecCSFlags(), &requirementObject) == errSecSuccess,
              let code, let requirementObject else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirementObject) == errSecSuccess
    }

    public func signatureMatchesRunning(processID: Int32, requirement: String) -> Bool {
        var code: SecCode?
        var requirementObject: SecRequirement?
        let attributes = [kSecGuestAttributePid: processID] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code) == errSecSuccess,
              SecRequirementCreateWithString(requirement as CFString, SecCSFlags(), &requirementObject) == errSecSuccess,
              let code, let requirementObject else { return false }
        return SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirementObject) == errSecSuccess
    }

    public func runningApps(bundleIdentifier: String) -> [RegisteredRunningApp] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).map {
            RegisteredRunningApp(processID: $0.processIdentifier, bundleURL: $0.bundleURL)
        }
    }

    public func open(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    public func terminate(processID: Int32) -> Bool {
        NSRunningApplication(processIdentifier: processID)?.terminate() ?? false
    }

    public func isRunning(processID: Int32) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: processID) else { return false }
        return !app.isTerminated
    }
}
