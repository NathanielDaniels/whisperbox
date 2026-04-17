// app/Sources/WhisperBox/SocketClient.swift
import Foundation

/// Communicates with the Python transcription service over a Unix domain socket.
/// Protocol: newline-delimited JSON.
class SocketClient {
    private let socketPath: String
    private var fd: Int32 = -1
    private var isConnected = false
    private let readQueue = DispatchQueue(label: "whisperbox.socket.read")
    private let writeQueue = DispatchQueue(label: "whisperbox.socket.write")

    var onEvent: (([String: Any]) -> Void)?

    init(socketPath: String? = nil) {
        self.socketPath = socketPath ?? NSString(
            string: "~/.local/share/whisperbox/whisperbox.sock"
        ).expandingTildeInPath
    }

    func connect() {
        // Create Unix domain socket
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            print("[WhisperBox] Failed to create socket")
            return
        }

        // Build sockaddr_un
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { dest in
                _ = strcpy(dest, ptr)
            }
        }

        // Connect
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, addrLen)
            }
        }

        guard result == 0 else {
            print("[WhisperBox] Failed to connect: errno=\(errno)")
            Darwin.close(fd)
            fd = -1
            return
        }

        isConnected = true

        // Start reading on background queue
        readQueue.async { [weak self] in
            self?.readLoop()
        }
    }

    func sendCommand(_ command: [String: Any]) {
        writeQueue.async { [weak self] in
            guard let self = self, self.isConnected, self.fd >= 0 else { return }
            guard let data = try? JSONSerialization.data(withJSONObject: command),
                  let jsonString = String(data: data, encoding: .utf8) else { return }

            let line = jsonString + "\n"
            line.utf8.withContiguousStorageIfAvailable { buf in
                Darwin.write(self.fd, buf.baseAddress!, buf.count)
            }
        }
    }

    func disconnect() {
        isConnected = false
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    private func readLoop() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var accumulated = Data()

        while isConnected {
            let bytesRead = Darwin.read(fd, &buffer, buffer.count)
            if bytesRead <= 0 {
                isConnected = false
                break
            }

            accumulated.append(contentsOf: buffer[0..<bytesRead])

            // Process complete newline-delimited JSON lines
            while let newlineIndex = accumulated.firstIndex(of: 0x0A) {
                let lineData = accumulated.subdata(in: accumulated.startIndex..<newlineIndex)
                accumulated.removeSubrange(accumulated.startIndex...newlineIndex)

                if let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                    DispatchQueue.main.async { [weak self] in
                        self?.onEvent?(json)
                    }
                }
            }
        }
    }
}
