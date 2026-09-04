import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private func requireSocket(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

#if canImport(Darwin)
private let testSocketStreamType = SOCK_STREAM
#else
private let testSocketStreamType = Int32(SOCK_STREAM.rawValue)
#endif

private func connectUnixSocket(path: String) throws -> Int32 {
    let fd = socket(AF_UNIX, testSocketStreamType, 0)
    guard fd >= 0 else { throw NSError(domain: "socket-test", code: 1) }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
    guard path.utf8.count < maxPathLength else {
        close(fd)
        throw NSError(domain: "socket-test", code: 2)
    }

    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: maxPathLength) { chars in
            chars.initialize(repeating: 0, count: maxPathLength)
            _ = path.withCString { source in strcpy(chars, source) }
        }
    }

    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else {
        close(fd)
        throw NSError(domain: "socket-test", code: 3)
    }
    return fd
}

private func writeAll(fd: Int32, data: Data) throws {
    try data.withUnsafeBytes { rawBuffer in
        guard let base = rawBuffer.baseAddress else { return }
        var offset = 0
        while offset < rawBuffer.count {
            let count = write(fd, base.advanced(by: offset), rawBuffer.count - offset)
            guard count > 0 else { throw NSError(domain: "socket-test", code: 4) }
            offset += count
        }
    }
}

private func readExactly(fd: Int32, count: Int) throws -> Data {
    var data = Data(count: count)
    var offset = 0
    try data.withUnsafeMutableBytes { rawBuffer in
        guard let base = rawBuffer.baseAddress else { return }
        while offset < count {
            let n = read(fd, base.advanced(by: offset), count - offset)
            guard n > 0 else { throw NSError(domain: "socket-test", code: 5) }
            offset += n
        }
    }
    return data
}

private func readFrame(fd: Int32) throws -> Data {
    let header = try readExactly(fd: fd, count: 4)
    let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    let payload = try readExactly(fd: fd, count: Int(length))
    var frame = header
    frame.append(payload)
    return frame
}

@main
struct PrismBuild52SocketTests {
    static func main() throws {
        let host = PrismBuild52RuntimeServiceHost(
            runtimeIdentity: "dev.relaxin.runtime",
            displayName: "RELAXIN-X Runtime",
            serviceVersion: "0.1.0",
            supportedProtocolVersions: [1],
            providerKind: .native,
            priority: 100,
            capabilityStates: [],
            health: .healthy,
            backgroundSessionState: .unavailable,
            metadata: ["serviceID": "dev.relaxin.service.runtime"]
        )
        let processor = PrismRuntimeServiceFrameProcessor(host: host)
        let socketPath = "/tmp/relaxinx-prism-\(getpid()).sock"
        let server = PrismUnixSocketRuntimeServiceServer(path: socketPath, processor: processor)
        try server.start()
        defer { server.stop() }

        Thread.sleep(forTimeInterval: 0.05)

        let clientFD = try connectUnixSocket(path: socketPath)
        defer { close(clientFD) }

        let requestJSON = Data(#"{"handshake":{"_0":{"clientIdentifier":"dev.allenux.prism","supportedProtocolVersions":[1]}}}"#.utf8)
        let requestFrame = try PrismLengthPrefixedJSONCodec().encodePayload(requestJSON)
        try writeAll(fd: clientFD, data: requestFrame)

        let responseFrame = try readFrame(fd: clientFD)
        let responseJSON = try PrismLengthPrefixedJSONCodec().decodeFrame(responseFrame)
        let object = try JSONSerialization.jsonObject(with: responseJSON) as? [String: Any]
        let helloBox = object?["hello"] as? [String: Any]
        let hello = helloBox?["_0"] as? [String: Any]
        requireSocket(hello?["runtimeIdentity"] as? String == "dev.relaxin.runtime", "socket round-trip must return runtime hello")
        requireSocket(FileManager.default.fileExists(atPath: socketPath), "socket endpoint should exist while server is running")

        server.stop()
        Thread.sleep(forTimeInterval: 0.02)
        requireSocket(!FileManager.default.fileExists(atPath: socketPath), "server stop must clean up its socket endpoint")

        print("PASS: Prism Build 52 Unix socket round-trip")
    }
}
