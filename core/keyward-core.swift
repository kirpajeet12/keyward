// keyward-core: seals secrets to a key that lives in this Mac's Secure Enclave.
//
// Sealing only needs the public key, so saving a secret never asks for Touch ID.
// Unsealing needs the Secure Enclave private key, which only works after Touch ID
// (or the Mac password) and never leaves the chip.
//
//   keyward-core status
//   keyward-core init
//   keyward-core seal              < plaintext            > base64 blob
//   keyward-core unseal --reason R [--biometrics-only] < base64 blobs (lines) > base64 plaintexts (lines)
//
// Blob format (v1): 0x01 | ephemeral P-256 public key (64 bytes, raw) | AES-GCM combined (nonce + ciphertext + tag)
// Key derivation: ECDH(ephemeral, enclave) -> HKDF-SHA256(salt: ephemeral public key, info: "keyward v1") -> AES-256 key.

import AppKit
import CryptoKit
import Foundation
import LocalAuthentication

let env = ProcessInfo.processInfo.environment
let dir = URL(fileURLWithPath: env["KEYWARD_HOME"] ?? (NSHomeDirectory() + "/.keyward"))
// Test-only mode: a software key file instead of the Secure Enclave, so the logic can be tested without Touch ID.
let insecureTest = env["KEYWARD_INSECURE_TEST_KEY"] == "1"
let keyFile = dir.appendingPathComponent(insecureTest ? "test-software-key" : "enclave-key")
let pubFile = dir.appendingPathComponent(insecureTest ? "test-software-key.pub" : "enclave-key.pub")
let info = Data("keyward v1".utf8)

// When launched as Keyward.app (via `open`), there is no stdin/stdout: results go to this file.
var resultFile: URL?

func fail(_ message: String, _ code: Int32 = 1) -> Never {
    if let out = resultFile {
        try? Data("ERR \(code) \(message)\n".utf8).write(to: out)
    }
    FileHandle.standardError.write(Data("keyward-core: \(message)\n".utf8))
    exit(code)
}

func writePrivate(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

func publicKey() -> P256.KeyAgreement.PublicKey {
    guard let raw = try? Data(contentsOf: pubFile), let key = try? P256.KeyAgreement.PublicKey(rawRepresentation: raw) else {
        fail("no vault key yet. Run: keyward init")
    }
    return key
}

func derive(_ shared: SharedSecret, salt: Data) -> SymmetricKey {
    shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: info, outputByteCount: 32)
}

func cmdStatus() {
    let hasKey = FileManager.default.fileExists(atPath: keyFile.path)
    print("secure_enclave=\(SecureEnclave.isAvailable) key=\(hasKey) mode=\(insecureTest ? "insecure-test" : "secure-enclave")")
}

func cmdInit() {
    if FileManager.default.fileExists(atPath: keyFile.path) { print("already initialized"); return }
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if insecureTest {
            let key = P256.KeyAgreement.PrivateKey()
            try writePrivate(key.rawRepresentation, to: keyFile)
            try writePrivate(key.publicKey.rawRepresentation, to: pubFile)
        } else {
            guard SecureEnclave.isAvailable else { fail("this Mac has no Secure Enclave") }
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                               [.privateKeyUsage, .userPresence], &error) else {
                fail("could not create access control: \(String(describing: error))")
            }
            // dataRepresentation is an opaque handle: only this Mac's Secure Enclave can use it.
            let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
            try writePrivate(key.dataRepresentation, to: keyFile)
            try writePrivate(key.publicKey.rawRepresentation, to: pubFile)
        }
        print("initialized")
    } catch {
        fail("init failed: \(error)")
    }
}

func cmdSeal() {
    let plaintext = FileHandle.standardInput.readDataToEndOfFile()
    do {
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let salt = ephemeral.publicKey.rawRepresentation
        let key = derive(try ephemeral.sharedSecretFromKeyAgreement(with: publicKey()), salt: salt)
        let box = try AES.GCM.seal(plaintext, using: key)
        var blob = Data([1])
        blob.append(salt)
        blob.append(box.combined!)
        print(blob.base64EncodedString())
    } catch {
        fail("seal failed: \(error)")
    }
}

func authenticate(reason: String, biometricsOnly: Bool) -> LAContext {
    // macOS only shows the Touch ID sheet for an app with a running main loop,
    // which is why unsealing runs inside Keyward.app (see keyward's unseal()).
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApp.activate(ignoringOtherApps: true)
    let context = LAContext()
    context.touchIDAuthenticationAllowableReuseDuration = 10
    // Fingerprint only: no password field and no "Use Password" button.
    let policy: LAPolicy = biometricsOnly ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
    if biometricsOnly {
        context.localizedFallbackTitle = ""
        var why: NSError?
        if !context.canEvaluatePolicy(policy, error: &why) {
            let code = (why as? LAError)?.code
            if code == .biometryLockout {
                fail("denied: Touch ID is locked. Unlock your Mac with your password once, then try again", 3)
            }
            fail("denied: Touch ID isn't available right now (is the Touch ID keyboard connected?). To allow your Mac password instead: keyward config password on", 3)
        }
    }
    var finished = false, ok = false
    var failure: Error?
    context.evaluatePolicy(policy, localizedReason: reason) { success, error in
        ok = success
        failure = error
        DispatchQueue.main.async { finished = true }
    }
    while !finished {
        RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
    }
    if !ok {
        if let la = failure as? LAError {
            switch la.code {
            case .userCancel: fail("denied: you cancelled the request", 3)
            case .systemCancel: fail("denied: macOS closed the prompt before it was answered", 3)
            case .biometryLockout: fail("denied: Touch ID is locked. Unlock your Mac with your password once, then try again", 3)
            case .authenticationFailed: fail("denied: fingerprint not recognised", 3)
            default: fail("denied: \(la.localizedDescription) (LAError \(la.code.rawValue))", 3)
            }
        }
        fail("denied: \(failure?.localizedDescription ?? "authentication failed")", 3)
    }
    return context
}

func cmdUnseal(reason: String, input: String, biometricsOnly: Bool) -> [String] {
    let blobs = input.split(whereSeparator: \.isNewline).map(String.init)
    guard let handle = try? Data(contentsOf: keyFile) else { fail("no vault key yet. Run: keyward init") }
    var out: [String] = []
    do {
        let agree: (P256.KeyAgreement.PublicKey) throws -> SharedSecret
        if insecureTest {
            let key = try P256.KeyAgreement.PrivateKey(rawRepresentation: handle)
            agree = { try key.sharedSecretFromKeyAgreement(with: $0) }
        } else {
            let context = authenticate(reason: reason, biometricsOnly: biometricsOnly)
            let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: handle, authenticationContext: context)
            agree = { try key.sharedSecretFromKeyAgreement(with: $0) }
        }
        for b64 in blobs {
            guard let blob = Data(base64Encoded: b64), blob.count > 65 + 28, blob.first == 1 else { fail("damaged secret") }
            let salt = blob.subdata(in: 1..<65)
            let shared = try agree(try P256.KeyAgreement.PublicKey(rawRepresentation: salt))
            let box = try AES.GCM.SealedBox(combined: blob.subdata(in: 65..<blob.count))
            out.append(try AES.GCM.open(box, using: derive(shared, salt: salt)).base64EncodedString())
        }
    } catch {
        fail("unseal failed: \(error)")
    }
    return out
}

func value(_ flag: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

var args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "status": cmdStatus()
case "init": cmdInit()
case "seal": cmdSeal()
case "unseal":
    // Two ways in: stdin/stdout (tests, software key), or --in/--out files when launched as Keyward.app.
    guard let reason = value("--reason", in: args) else { fail("usage: unseal --reason TEXT [--biometrics-only] [--in FILE --out FILE]") }
    let biometricsOnly = args.contains("--biometrics-only")
    if let inPath = value("--in", in: args), let outPath = value("--out", in: args) {
        resultFile = URL(fileURLWithPath: outPath)
        let input = (try? String(contentsOfFile: inPath, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(atPath: inPath)
        let lines = cmdUnseal(reason: reason, input: input, biometricsOnly: biometricsOnly)
        try? Data((["OK"] + lines).joined(separator: "\n").utf8).write(to: resultFile!)
    } else {
        let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        cmdUnseal(reason: reason, input: input, biometricsOnly: biometricsOnly).forEach { print($0) }
    }
default:
    fail("usage: keyward-core status|init|seal|unseal --reason TEXT [--in FILE --out FILE]", 2)
}
