import Foundation
import CryptoKit
let env = ProcessInfo.processInfo.environment
func stop(_ message: String) -> Never { fputs(message + "\n", stderr); exit(2) }
guard let address = env["WAVEDOCK_LICENSE_SERVER_URL"], let url = URL(string: address), url.scheme == "https", let host = url.host, !host.hasSuffix(".invalid"), url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else { stop("Commercial build requires WAVEDOCK_LICENSE_SERVER_URL: a valid HTTPS service origin.") }
guard let raw = env["WAVEDOCK_LICENSE_PUBLIC_KEY"], let data = Data(base64Encoded: raw), (try? P256.Signing.PublicKey(x963Representation: data)) != nil else { stop("Commercial build requires WAVEDOCK_LICENSE_PUBLIC_KEY: a valid base64 P-256 X9.63 public key.") }
guard let keyID = env["WAVEDOCK_LICENSE_KEY_ID"], !keyID.isEmpty, keyID.count < 80 else { stop("Commercial build requires WAVEDOCK_LICENSE_KEY_ID.") }
print("Commercial public configuration validated; provider readiness still requires sandbox verification.")
