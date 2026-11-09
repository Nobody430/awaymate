import Foundation
import CryptoKit

struct ServiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Kraken read-only access (API key with "Query Funds" permission only).
enum Kraken {
    static var key: String { Keychain.get("krakenKey") ?? "" }
    static var secret: String { Keychain.get("krakenSecret") ?? "" }
    static var isConfigured: Bool { !key.isEmpty && !secret.isEmpty }

    static func balances() async throws -> [String: Double] {
        let path = "/0/private/Balance"
        let nonce = String(UInt64(Date().timeIntervalSince1970 * 1000))
        let post = "nonce=\(nonce)"
        guard let secretData = Data(base64Encoded: secret) else { throw ServiceError(message: "Private Key ist ungültig.") }

        let sha = SHA256.hash(data: Data((nonce + post).utf8))
        var message = Data(path.utf8)
        message.append(contentsOf: sha)
        let signature = HMAC<SHA512>.authenticationCode(for: message, using: SymmetricKey(data: secretData))

        var request = URLRequest(url: URL(string: "https://api.kraken.com" + path)!)
        request.httpMethod = "POST"
        request.httpBody = Data(post.utf8)
        request.setValue(key, forHTTPHeaderField: "API-Key")
        request.setValue(Data(signature).base64EncodedString(), forHTTPHeaderField: "API-Sign")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError(message: "Ungültige Antwort.") }
        if let errors = json["error"] as? [String], let first = errors.first { throw ServiceError(message: first) }
        let result = json["result"] as? [String: Any] ?? [:]
        var out: [String: Double] = [:]
        for (asset, value) in result {
            guard let amount = Double("\(value)"), amount > 0 else { continue }
            out[normalize(asset), default: 0] += amount
        }
        return out
    }

    static func normalize(_ asset: String) -> String {
        var s = asset.uppercased()
        for suffix in [".HOLD", ".S", ".M", ".F", ".B", ".P"] where s.hasSuffix(suffix) { s = String(s.dropLast(suffix.count)) }
        if s.count == 4, let f = s.first, f == "X" || f == "Z",
           ["XXBT", "XETH", "XLTC", "XXRP", "XXLM", "XXMR", "XZEC", "XXDG", "XETC", "XMLN", "XREP",
            "ZCHF", "ZUSD", "ZEUR", "ZGBP", "ZJPY", "ZCAD", "ZAUD"].contains(s) {
            s = String(s.dropFirst())
        }
        if s.hasSuffix("2") && s.count > 3 { s = String(s.dropLast()) } // ETH2 → ETH
        return ["XBT": "BTC", "XDG": "DOGE"][s] ?? s
    }
}

/// CHF prices for crypto and fiat via Coinbase's public exchange-rates endpoint.
enum Prices {
    static func chf() async throws -> [String: Double] {
        let url = URL(string: "https://api.coinbase.com/v2/exchange-rates?currency=CHF")!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rates = (json["data"] as? [String: Any])?["rates"] as? [String: Any] else {
            throw ServiceError(message: "Kurse nicht verfügbar.")
        }
        var out: [String: Double] = [:]
        for (symbol, value) in rates {
            if let rate = Double("\(value)"), rate > 0 { out[symbol.uppercased()] = 1 / rate }
        }
        return out
    }
}

/// Reads balances of public addresses directly from the blockchain (works for Ledger accounts).
enum Chains {
    static func balance(_ w: WalletAddress) async throws -> Double {
        let address = w.address.trimmingCharacters(in: .whitespacesAndNewlines)
        switch w.chain {
        case .btc:
            let (data, _) = try await URLSession.shared.data(from: URL(string: "https://mempool.space/api/address/\(address)")!)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError(message: "Adresse unbekannt.") }
            func sats(_ key: String) -> Double {
                let s = json[key] as? [String: Any] ?? [:]
                return ((s["funded_txo_sum"] as? NSNumber)?.doubleValue ?? 0) - ((s["spent_txo_sum"] as? NSNumber)?.doubleValue ?? 0)
            }
            return (sats("chain_stats") + sats("mempool_stats")) / 100_000_000
        case .eth:
            let result = try await rpc("https://ethereum-rpc.publicnode.com", method: "eth_getBalance", params: [address, "latest"])
            guard let hex = result as? String else { throw ServiceError(message: "Ungültige Antwort.") }
            return hexToDouble(hex) / 1e18
        case .sol:
            let result = try await rpc("https://api.mainnet-beta.solana.com", method: "getBalance", params: [address])
            guard let value = (result as? [String: Any])?["value"] as? NSNumber else { throw ServiceError(message: "Ungültige Antwort.") }
            return value.doubleValue / 1e9
        }
    }

    private static func rpc(_ endpoint: String, method: String, params: [Any]) async throws -> Any {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError(message: "Ungültige Antwort.") }
        if let err = json["error"] as? [String: Any] { throw ServiceError(message: err["message"] as? String ?? "Fehler") }
        return json["result"] as Any
    }

    static func hexToDouble(_ hex: String) -> Double {
        hex.lowercased().replacingOccurrences(of: "0x", with: "").reduce(0.0) { acc, ch in
            acc * 16 + Double(ch.hexDigitValue ?? 0)
        }
    }
}
