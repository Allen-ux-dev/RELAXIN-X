import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

#if canImport(Darwin)
private let prismSocketStreamType = SOCK_STREAM
#else
private let prismSocketStreamType = Int32(SOCK_STREAM.rawValue)
#endif

enum PrismUnixSocketRuntimeServiceServerError: Error, Equatable {
    case alreadyRunning
    case endpointAlreadyExists
    case pathTooLong
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case malformedFrame
    case peerDisconnected
    case readFailed(Int32)
    case writeFailed(Int32)
}

final class PrismUnixSocketRuntimeServiceServer: @unchecked Sendable {
    let path: String
    let processor: PrismRuntimeServiceFrameProcessor

    private let stateLock = NSLock()
    private let workerQueue = DispatchQueue(label: "dev.relaxin.prism-runtime-service-host")
    private var listenerFD: Int32 = -1
    private var running = false

    init(path: String, processor: PrismRuntimeServiceFrameProcessor) {
        self.path = path
        self.processor = processor
    }

    deinit {
        stop()
    }

    func start() throws {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !running else {
            throw PrismUnixSocketRuntimeServiceServerError.alreadyRunning
        }
        guard !FileManager.default.fileExists(atPath: path) else {
            throw PrismUnixSocketRuntimeServiceServerError.endpointAlreadyExists
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maximumPathLength = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < maximumPathLength else {
            throw PrismUnixSocketRuntimeServiceServerError.pathTooLong
        }

        let fd = socket(AF_UNIX, prismSocketStreamType, 0)
        guard fd >= 0 else {
            throw PrismUnixSocketRuntimeServiceServerError.socketCreationFailed(errno)
        }

        var shouldClose = true
        defer {
            if shouldClose {
                close(fd)
            }
        }

        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: maximumPathLength) { chars in
                chars.initialize(repeating: 0, count: maximumPathLength)
                path.withCString { source in
                    _ = strcpy(chars, source)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            throw PrismUnixSocketRuntimeServiceServerError.bindFailed(errno)
        }

        guard listen(fd, 4) == 0 else {
            let savedErrno = errno
            unlink(path)
            throw PrismUnixSocketRuntimeServiceServerError.listenFailed(savedErrno)
        }

        listenerFD = fd
        running = true
        shouldClose = false

        workerQueue.async { [weak self] in
            self?.acceptLoop(listenerFD: fd)
        }
    }

    func stop() {
        let fd: Int32

        stateLock.lock()
        if !running {
            stateLock.unlock()
            return
        }
        running = false
        fd = listenerFD
        listenerFD = -1
        stateLock.unlock()

        if fd >= 0 {
            _ = shutdown(fd, Int32(SHUT_RDWR))
            close(fd)
        }
        unlink(path)
    }

    private func acceptLoop(listenerFD: Int32) {
        while isRunning {
            let clientFD = accept(listenerFD, nil, nil)
            if clientFD < 0 {
                if !isRunning { return }
                if errno == EINTR { continue }
                continue
            }

            handleClient(fd: clientFD)
            close(clientFD)
        }
    }

    private func handleClient(fd: Int32) {
        while isRunning {
            do {
                let header = try readExactly(fd: fd, count: 4)
                let payloadLength = header.reduce(UInt32(0)) { partial, byte in
                    (partial << 8) | UInt32(byte)
                }
                guard payloadLength <= UInt32(PrismLengthPrefixedJSONCodec.build52MaximumPayloadBytes) else {
                    return
                }

                let payload = try readExactly(fd: fd, count: Int(payloadLength))
                var requestFrame = header
                requestFrame.append(payload)
                let responseFrame = try processor.handleFrame(requestFrame)
                try writeAll(fd: fd, data: responseFrame)
            } catch PrismUnixSocketRuntimeServiceServerError.peerDisconnected {
                return
            } catch {
                return
            }
        }
    }

    private var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running
    }

    private func readExactly(fd: Int32, count: Int) throws -> Data {
        var data = Data(count: count)
        var offset = 0

        try data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            while offset < count {
                let result = read(fd, baseAddress.advanced(by: offset), count - offset)
                if result == 0 {
                    throw PrismUnixSocketRuntimeServiceServerError.peerDisconnected
                }
                if result < 0 {
                    if errno == EINTR { continue }
                    throw PrismUnixSocketRuntimeServiceServerError.readFailed(errno)
                }
                offset += result
            }
        }
        return data
    }

    private func writeAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let result = write(fd, baseAddress.advanced(by: offset), rawBuffer.count - offset)
                if result < 0 {
                    if errno == EINTR { continue }
                    throw PrismUnixSocketRuntimeServiceServerError.writeFailed(errno)
                }
                guard result > 0 else {
                    throw PrismUnixSocketRuntimeServiceServerError.peerDisconnected
                }
                offset += result
            }
        }
    }
}
