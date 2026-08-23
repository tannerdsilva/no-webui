import Foundation
import PackagePlugin

// connect-based port probe. reports whether something is listening on
// 127.0.0.1:<port>. a bind-based check is impossible inside the sandbox
// (bind() is denied with EPERM); a client connect is allowed.

@main
struct WebUIProbePlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let portText = arguments.first ?? "9123"
        let port = Int(portText) ?? 9123

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            Diagnostics.error("socket() failed errno=\(errno)")
            return
        }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let r = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if r == 0 {
            print("IN USE on :\(port) (connect succeeded)")
        } else {
            print("FREE on :\(port) (connect refused, errno=\(errno))")
        }
    }
}
