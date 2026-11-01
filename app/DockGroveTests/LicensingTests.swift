import Foundation
import CryptoKit
@testable import DockGrove

func runLicensingTests() throws {
        let key = P256.Signing.PrivateKey()
        let device = UUID().uuidString, now = Date()
        let claims = LicenseClaims(iss: "dockgrove", aud: "com.dylan.wavedock", licenseId: "test-license", deviceHash: LicenseVerifier.deviceHash(device), majorVersion: 1, environment: "test", iat: now.timeIntervalSince1970, exp: now.timeIntervalSince1970 + 30*86400)
        func sign(_ claims: LicenseClaims) throws -> SignedLicense {
            let payload = try JSONEncoder().encode(claims).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            let signature = try key.signature(for: Data(payload.utf8)).rawRepresentation.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            return SignedLicense(payload: payload, signature: signature, keyId: "test-1")
        }
        let signed = try sign(claims)
        func verify(_ signed: SignedLicense, deviceID: String? = nil, date: Date? = nil) throws {
            _ = try LicenseVerifier.verify(signed, publicKey: key.publicKey.x963Representation, keyID: "test-1", device: deviceID ?? device, now: date ?? now)
        }
        func rejects(_ action: () throws -> Void) {
            do { try action(); fatalError("Invalid license accepted") } catch { }
        }
        try verify(signed)
        rejects { try verify(signed, deviceID: UUID().uuidString) }
        rejects { try verify(signed, date: now.addingTimeInterval(31*86400)) }
        var tampered = signed; tampered.payload += "a"; rejects { try verify(tampered) }
        tampered = signed; tampered.keyId = "other"; rejects { try verify(tampered) }
        for field in ["aud", "environment", "majorVersion", "future", "excess"] {
            var changed = claims
            if field == "aud" { changed.aud = "another-app" }
            if field == "environment" { changed.environment = "live" }
            if field == "majorVersion" { changed.majorVersion = 2 }
            if field == "future" { changed.iat += 1000; changed.exp += 1000 }
            if field == "excess" { changed.exp += 86400 }
            let altered = try sign(changed); rejects { try verify(altered) }
        }
        print("License verifier: valid offline signature, tampering, wrong device/key/app/environment/version, expiration and lifetime bounds passed.")
}
