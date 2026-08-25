//
//  main.swift
//  macengine-cli
//
//  The second front door, from the outside.
//
//  This deliberately shares no code with the app. It speaks the diagnostic
//  socket's text protocol over AF_UNIX and prints what comes back, which is
//  the whole argument for having a text protocol: the client needs no wire
//  types, no XPC interface, and no framework — `nc -U` is a valid client and
//  so is this.
//
//  Scope worth stating plainly: this queries a service that is already
//  running. It does not launch one. The monitoring service is a bundled XPC
//  service owned by launchd on the app's behalf, so `status` answers while
//  MacEngine is running and reports that it is not otherwise.
//

import Foundation

let socketPath = "/tmp/macengine-diagnostic.sock"

// MARK: - Usage

func usage() -> String {
    """
    macengine-cli — query a running MacEngine monitoring service

    USAGE
      macengine-cli <command>

    COMMANDS
      status      Service and machine state, human readable  (default)
      snapshot    The latest MetricSnapshot as JSON
      processes   Top processes, sampled locally — works with no service
      help        This text

    The first two ask the running service over \(socketPath).
    `processes` reads the kernel directly and needs nothing running.
    """
}

// MARK: - Socket client

enum ClientError: Error, CustomStringConvertible {
    case noSocket
    case refused(Int32)
    case failed(String)

    var description: String {
        switch self {
        case .noSocket:
            "no diagnostic socket at \(socketPath) — is MacEngine running?"
        case .refused(let code) where code == ECONNREFUSED:
            // The node outlives the process that bound it, so "the file is
            // there" and "someone is listening" are different questions.
            "\(socketPath) is stale — the monitoring service is not running"
        case .refused(let code):
            "could not connect to \(socketPath): \(String(cString: strerror(code)))"
        case .failed(let reason):
            reason
        }
    }
}

/// One request, one reply, one connection. Reads until the service hangs up,
/// which is how it signals the end of a reply — there is no length prefix
/// because there is no need for one.
func ask(_ verb: String) throws -> String {
    guard FileManager.default.fileExists(atPath: socketPath) else { throw ClientError.noSocket }

    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw ClientError.refused(errno) }
    defer { close(descriptor) }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutablePointer(to: &address.sun_path) { field in
        field.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: field.pointee)) { bytes in
            _ = strcpy(bytes, socketPath)
        }
    }

    let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
            connect(descriptor, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else { throw ClientError.refused(errno) }

    var timeout = timeval(tv_sec: 5, tv_usec: 0)
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    let request = Array((verb + "\n").utf8)
    var sent = 0
    while sent < request.count {
        let wrote = request.withUnsafeBytes { buffer in
            write(descriptor, buffer.baseAddress!.advanced(by: sent), buffer.count - sent)
        }
        guard wrote > 0 else { throw ClientError.failed("write to socket failed") }
        sent += wrote
    }

    var reply = Data()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
        let got = read(descriptor, &chunk, chunk.count)
        if got > 0 {
            reply.append(contentsOf: chunk[0..<got])
        } else if got == 0 {
            break
        } else {
            throw ClientError.failed("read from socket failed")
        }
    }

    return String(decoding: reply, as: UTF8.self).trimmingCharacters(in: .newlines)
}

// MARK: - Local process listing

/// Formats what the Objective-C enumerator returned. The C API work lives in
/// `ProcessEnumerator`; this is only presentation.
func localProcesses(limit: Int = 10) -> String {
    let processes = ProcessEnumerator.topProcesses(byResidentSize: UInt(limit))

    guard !processes.isEmpty else {
        return "no processes readable — every pid refused proc_pid_rusage"
    }

    func column(_ text: String, _ width: Int) -> String {
        text.count > width
            ? String(text.prefix(width - 1)) + "…"
            : text.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    var lines = [column("PID", 8) + column("PROCESS", 30) + "RESIDENT"]
    for process in processes {
        lines.append(
            column("\(process.processIdentifier)", 8)
            + column(process.name, 30)
            + megabytes(process.residentBytes)
        )
    }
    return lines.joined(separator: "\n")
}

func megabytes(_ bytes: UInt64) -> String {
    String(format: "%.1f MB", Double(bytes) / 1_000_000)
}

// MARK: - Entry

let arguments = CommandLine.arguments.dropFirst()
let command = arguments.first ?? "status"

switch command {
case "help", "-h", "--help":
    print(usage())

case "processes":
    print(localProcesses())

case "status", "snapshot":
    do {
        print(try ask(command))
    } catch {
        FileHandle.standardError.write(Data("macengine-cli: \(error)\n".utf8))
        exit(1)
    }

default:
    FileHandle.standardError.write(Data("macengine-cli: unknown command \"\(command)\"\n\n".utf8))
    print(usage())
    exit(2)
}
