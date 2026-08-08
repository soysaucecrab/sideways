import Foundation
import Network

/// Handles one SOCKS5 client (the Mac, via the USB tunnel):
///  1. Greeting: version + auth-method negotiation (we accept "no auth" only).
///  2. Request: CONNECT with IPv4 / IPv6 / domain-name address types.
///  3. Relay: pipe bytes both ways between the Mac and the outbound socket.
///
/// Remote DNS: domain-name requests are handed straight to `NWConnection` with
/// an `NWEndpoint.hostPort(host: .name(...))`, so resolution happens on the
/// phone — the Mac never needs its own DNS.
final class SOCKS5Connection {

    // SOCKS5 constants (RFC 1928).
    private enum V { static let socks5: UInt8 = 0x05 }
    private enum Auth { static let none: UInt8 = 0x00; static let unacceptable: UInt8 = 0xFF }
    private enum Cmd { static let connect: UInt8 = 0x01 }
    private enum Atyp { static let ipv4: UInt8 = 0x01; static let domain: UInt8 = 0x03; static let ipv6: UInt8 = 0x04 }
    private enum Reply {
        static let succeeded: UInt8 = 0x00
        static let generalFailure: UInt8 = 0x01
        static let connectionRefused: UInt8 = 0x05
        static let commandNotSupported: UInt8 = 0x07
        static let addressTypeNotSupported: UInt8 = 0x08
    }

    let id: Int
    private let inbound: NWConnection
    private var outbound: NWConnection?
    private let queue: DispatchQueue
    private let requireCellular: Bool
    private let stats: ProxyStats
    private let onClose: (Int) -> Void
    private var closed = false

    init(id: Int,
         inbound: NWConnection,
         queue: DispatchQueue,
         requireCellular: Bool,
         stats: ProxyStats,
         onClose: @escaping (Int) -> Void) {
        self.id = id
        self.inbound = inbound
        self.queue = queue
        self.requireCellular = requireCellular
        self.stats = stats
        self.onClose = onClose
    }

    func start() {
        inbound.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.cancel() }
            if case .cancelled = state { self?.finish() }
        }
        inbound.start(queue: queue)
        readGreeting()
    }

    // MARK: - Handshake step 1: greeting

    private func readGreeting() {
        // VER(1) NMETHODS(1) then NMETHODS bytes.
        receiveExact(from: inbound, count: 2) { [weak self] header in
            guard let self, let header, header.count == 2, header[0] == V.socks5 else {
                self?.cancel(); return
            }
            let nMethods = Int(header[1])
            guard nMethods > 0 else { self.cancel(); return }
            self.receiveExact(from: self.inbound, count: nMethods) { methods in
                guard let methods, methods.contains(Auth.none) else {
                    // Reject: no acceptable auth method.
                    self.send(to: self.inbound, data: Data([V.socks5, Auth.unacceptable])) {
                        self.cancel()
                    }
                    return
                }
                self.send(to: self.inbound, data: Data([V.socks5, Auth.none])) {
                    self.readRequest()
                }
            }
        }
    }

    // MARK: - Handshake step 2: request

    private func readRequest() {
        // VER(1) CMD(1) RSV(1) ATYP(1) then variable address + PORT(2).
        receiveExact(from: inbound, count: 4) { [weak self] head in
            guard let self, let head, head.count == 4, head[0] == V.socks5 else {
                self?.cancel(); return
            }
            let cmd = head[1]
            let atyp = head[3]

            guard cmd == Cmd.connect else {
                self.replyFailure(Reply.commandNotSupported); return
            }

            switch atyp {
            case Atyp.ipv4:
                self.receiveExact(from: self.inbound, count: 4 + 2) { body in
                    guard let body, body.count == 6 else { self.cancel(); return }
                    let host = body[0..<4].map(String.init).joined(separator: ".")
                    let port = UInt16(body[4]) << 8 | UInt16(body[5])
                    self.openOutbound(host: .ipv4(host), port: port)
                }
            case Atyp.ipv6:
                self.receiveExact(from: self.inbound, count: 16 + 2) { body in
                    guard let body, body.count == 18 else { self.cancel(); return }
                    let port = UInt16(body[16]) << 8 | UInt16(body[17])
                    let addr = Data(body[0..<16])
                    self.openOutbound(host: .ipv6(addr), port: port)
                }
            case Atyp.domain:
                self.receiveExact(from: self.inbound, count: 1) { lenByte in
                    guard let lenByte, let n = lenByte.first else { self.cancel(); return }
                    self.receiveExact(from: self.inbound, count: Int(n) + 2) { body in
                        guard let body, body.count == Int(n) + 2 else { self.cancel(); return }
                        let host = String(decoding: body[0..<Int(n)], as: UTF8.self)
                        let port = UInt16(body[Int(n)]) << 8 | UInt16(body[Int(n) + 1])
                        self.openOutbound(host: .name(host), port: port)
                    }
                }
            default:
                self.replyFailure(Reply.addressTypeNotSupported)
            }
        }
    }

    // MARK: - Outbound (cellular) connection

    private enum TargetHost {
        case ipv4(String)
        case ipv6(Data)
        case name(String)

        var endpointHost: NWEndpoint.Host {
            switch self {
            case .ipv4(let s): return .init(s)
            case .name(let s): return .init(s)
            case .ipv6(let data):
                if let ipv6 = IPv6Address(data) { return .ipv6(ipv6) }
                return .init("::")
            }
        }
    }

    private func openOutbound(host: TargetHost, port: UInt16) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            replyFailure(Reply.generalFailure); return
        }

        let params = NWParameters.tcp
        if requireCellular {
            // Force the outbound path over cellular so traffic leaves as
            // ordinary phone traffic (spec §5.1).
            params.requiredInterfaceType = .cellular
            params.prohibitedInterfaceTypes = [.wifi, .wiredEthernet]
        }

        let out = NWConnection(host: host.endpointHost, port: nwPort, using: params)
        self.outbound = out

        out.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.replySuccess()
                self.relay()
            case .waiting(let error):
                // No cellular path available yet — fail fast rather than hang.
                self.replyFailure(self.reply(for: error))
            case .failed(let error):
                self.replyFailure(self.reply(for: error))
            case .cancelled:
                self.cancel()
            default:
                break
            }
        }
        out.start(queue: queue)
    }

    private func reply(for error: NWError) -> UInt8 {
        if case .posix(let code) = error, code == .ECONNREFUSED {
            return Reply.connectionRefused
        }
        return Reply.generalFailure
    }

    // MARK: - Replies

    private func replySuccess() {
        // BND.ADDR / BND.PORT are unused by clients here; send zeros.
        var reply = Data([V.socks5, Reply.succeeded, 0x00, Atyp.ipv4])
        reply.append(contentsOf: [0, 0, 0, 0, 0, 0])
        send(to: inbound, data: reply, then: nil)
    }

    private func replyFailure(_ code: UInt8) {
        var reply = Data([V.socks5, code, 0x00, Atyp.ipv4])
        reply.append(contentsOf: [0, 0, 0, 0, 0, 0])
        send(to: inbound, data: reply) { [weak self] in self?.cancel() }
    }

    // MARK: - Bidirectional relay

    /// Directions still relaying. Both `pump` loops run on `queue`, so this is
    /// mutated serially without a lock. The connection is torn down only once
    /// both directions have reached EOF — preserving half-open TCP (a client
    /// may close its write side while the server keeps sending).
    private var openDirections = 2

    private func relay() {
        guard let outbound else { cancel(); return }
        pump(from: inbound, to: outbound, countOutbound: true)   // Mac → internet
        pump(from: outbound, to: inbound, countOutbound: false)  // internet → Mac
    }

    private func pump(from: NWConnection, to: NWConnection, countOutbound: Bool) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                if countOutbound { self.stats.addBytesOut(data.count) }
                else { self.stats.addBytesIn(data.count) }
                to.send(content: data, completion: .contentProcessed { sendError in
                    if sendError != nil { self.cancel(); return }
                    self.pump(from: from, to: to, countOutbound: countOutbound)
                })
            } else if error != nil {
                self.cancel()
            } else if isComplete {
                // This direction hit EOF: forward the FIN (half-close the peer)
                // and retire the direction. Tear down once both are done.
                to.send(content: nil, isComplete: true, completion: .contentProcessed { _ in })
                self.directionFinished()
            } else {
                self.pump(from: from, to: to, countOutbound: countOutbound)
            }
        }
    }

    private func directionFinished() {
        openDirections -= 1
        if openDirections <= 0 { cancel() }
    }

    // MARK: - I/O helpers

    /// Receive exactly `count` bytes (SOCKS framing needs precise reads).
    private func receiveExact(from conn: NWConnection, count: Int, completion: @escaping (Data?) -> Void) {
        conn.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, isComplete, error in
            if let error { _ = error; completion(nil); return }
            if let data, data.count == count { completion(data) }
            else if isComplete { completion(nil) }
            else { completion(data) }
        }
    }

    private func send(to conn: NWConnection, data: Data, then: (() -> Void)?) {
        conn.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil { self?.cancel(); return }
            then?()
        })
    }

    private func send(to conn: NWConnection, data: Data, completion: @escaping () -> Void) {
        send(to: conn, data: data, then: completion)
    }

    // MARK: - Teardown

    func cancel() {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            self.inbound.cancel()
            self.outbound?.cancel()
            self.finish()
        }
    }

    private func finish() {
        guard !closed else { return }
        closed = true
        onClose(id)
    }
}
