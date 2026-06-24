import Darwin
import Foundation

public struct LocalPTYProcessConfiguration: Equatable, Sendable {
    public var executablePath: String
    public var arguments: [String]
    public var workingDirectoryPath: String?
    public var environment: [String: String]
    public var columns: Int
    public var rows: Int

    public init(
        executablePath: String,
        arguments: [String],
        workingDirectoryPath: String? = nil,
        environment: [String: String] = [:],
        columns: Int = 120,
        rows: Int = 32
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectoryPath = workingDirectoryPath
        self.environment = environment
        self.columns = columns
        self.rows = rows
    }
}

public enum LocalPTYProcessError: Error, CustomStringConvertible, Equatable {
    case alreadyStarted
    case notStarted
    case openPTYFailed(errnoCode: Int32)
    case spawnFailed(errnoCode: Int32)
    case writeFailed(errnoCode: Int32)
    case resizeFailed(errnoCode: Int32)

    public var description: String {
        switch self {
        case .alreadyStarted:
            "PTY process has already started"
        case .notStarted:
            "PTY process has not started"
        case let .openPTYFailed(errnoCode):
            "openpty failed: \(String(cString: strerror(errnoCode)))"
        case let .spawnFailed(errnoCode):
            "posix_spawn failed: \(String(cString: strerror(errnoCode)))"
        case let .writeFailed(errnoCode):
            "PTY write failed: \(String(cString: strerror(errnoCode)))"
        case let .resizeFailed(errnoCode):
            "PTY resize failed: \(String(cString: strerror(errnoCode)))"
        }
    }
}

public final class LocalPTYProcess: @unchecked Sendable {
    private let configuration: LocalPTYProcessConfiguration
    private let lock = NSLock()
    private let readQueue = DispatchQueue(label: "PaperCodex.LocalPTYProcess.read", qos: .userInitiated)
    private let exitSemaphore = DispatchSemaphore(value: 0)
    private var masterFD: Int32?
    private var processID: pid_t?
    private var hasStarted = false
    private var running = false
    private var exitStatus: Int32?

    public init(configuration: LocalPTYProcessConfiguration) {
        self.configuration = configuration
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    public func start(onOutput: @escaping @Sendable (Data) -> Void) throws {
        let argvStrings = [configuration.executablePath] + configuration.arguments
        let workingDirectoryURL = normalized(configuration.workingDirectoryPath)
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        var environment = AgentRuntimeEnvironment.sanitizedProcessEnvironment(
            workingDirectoryURL: workingDirectoryURL,
            executablePath: configuration.executablePath,
            environmentOverrides: configuration.environment
        )
        if environment["TERM"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            environment["TERM"] = "xterm-256color"
        }
        if environment["COLORTERM"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            environment["COLORTERM"] = "truecolor"
        }
        let environmentStrings = environment
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }

        var master: Int32 = -1
        var slave: Int32 = -1
        var slaveName = [CChar](repeating: 0, count: Int(PATH_MAX))
        var windowSize = winsize(
            ws_row: UInt16(clamping: configuration.rows),
            ws_col: UInt16(clamping: configuration.columns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        guard openpty(&master, &slave, &slaveName, nil, &windowSize) == 0 else {
            throw LocalPTYProcessError.openPTYFailed(errnoCode: errno)
        }
        let slavePath = String(decoding: slaveName.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)

        var argvPointers = argvStrings.map { strdup($0) } + [nil]
        var environmentPointers = environmentStrings.map { strdup($0) } + [nil]
        defer {
            for pointer in argvPointers {
                free(pointer)
            }
            for pointer in environmentPointers {
                free(pointer)
            }
        }

        lock.lock()
        if hasStarted {
            lock.unlock()
            Darwin.close(master)
            Darwin.close(slave)
            throw LocalPTYProcessError.alreadyStarted
        }
        hasStarted = true
        lock.unlock()

        var fileActions: posix_spawn_file_actions_t?
        var spawnStatus = posix_spawn_file_actions_init(&fileActions)
        guard spawnStatus == 0 else {
            Darwin.close(master)
            Darwin.close(slave)
            throw LocalPTYProcessError.spawnFailed(errnoCode: spawnStatus)
        }
        defer {
            posix_spawn_file_actions_destroy(&fileActions)
        }

        spawnStatus = posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, slavePath, O_RDWR, 0)
        if spawnStatus == 0 {
            spawnStatus = posix_spawn_file_actions_adddup2(&fileActions, STDIN_FILENO, STDOUT_FILENO)
        }
        if spawnStatus == 0 {
            spawnStatus = posix_spawn_file_actions_adddup2(&fileActions, STDIN_FILENO, STDERR_FILENO)
        }
        if spawnStatus == 0 {
            spawnStatus = posix_spawn_file_actions_addclose(&fileActions, master)
        }
        if spawnStatus == 0 {
            spawnStatus = posix_spawn_file_actions_addclose(&fileActions, slave)
        }
        if spawnStatus == 0, let workingDirectoryPath = normalized(configuration.workingDirectoryPath) {
            if #available(macOS 26.0, *) {
                spawnStatus = posix_spawn_file_actions_addchdir(&fileActions, workingDirectoryPath)
            } else {
                spawnStatus = posix_spawn_file_actions_addchdir_np(&fileActions, workingDirectoryPath)
            }
        }
        guard spawnStatus == 0 else {
            Darwin.close(master)
            Darwin.close(slave)
            throw LocalPTYProcessError.spawnFailed(errnoCode: spawnStatus)
        }

        var attributes: posix_spawnattr_t?
        spawnStatus = posix_spawnattr_init(&attributes)
        guard spawnStatus == 0 else {
            Darwin.close(master)
            Darwin.close(slave)
            throw LocalPTYProcessError.spawnFailed(errnoCode: spawnStatus)
        }
        defer {
            posix_spawnattr_destroy(&attributes)
        }
        let flags = Int16(POSIX_SPAWN_SETSID)
        spawnStatus = posix_spawnattr_setflags(&attributes, flags)
        guard spawnStatus == 0 else {
            Darwin.close(master)
            Darwin.close(slave)
            throw LocalPTYProcessError.spawnFailed(errnoCode: spawnStatus)
        }

        var pid: pid_t = 0
        spawnStatus = configuration.executablePath.withCString { executableCString in
            posix_spawn(
                &pid,
                executableCString,
                &fileActions,
                &attributes,
                &argvPointers,
                &environmentPointers
            )
        }
        guard spawnStatus == 0 else {
            Darwin.close(master)
            Darwin.close(slave)
            throw LocalPTYProcessError.spawnFailed(errnoCode: spawnStatus)
        }

        Darwin.close(slave)
        lock.lock()
        masterFD = master
        processID = pid
        running = true
        lock.unlock()

        let masterFDForRead = master
        let processIDForWait = pid
        readQueue.async { [weak self] in
            self?.readUntilExit(masterFD: masterFDForRead, processID: processIDForWait, onOutput: onOutput)
        }
    }

    public func write(_ text: String) throws {
        try write(Data(text.utf8))
    }

    public func write(_ data: Data) throws {
        guard !data.isEmpty else {
            return
        }
        let fd = try currentMasterFD()
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            var offset = 0
            while offset < data.count {
                let written = Darwin.write(fd, baseAddress.advanced(by: offset), data.count - offset)
                if written < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw LocalPTYProcessError.writeFailed(errnoCode: errno)
                }
                offset += written
            }
        }
    }

    public func resize(columns: Int, rows: Int) throws {
        let fd = try currentMasterFD()
        var windowSize = winsize(
            ws_row: UInt16(clamping: rows),
            ws_col: UInt16(clamping: columns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        guard ioctl(fd, TIOCSWINSZ, &windowSize) == 0 else {
            throw LocalPTYProcessError.resizeFailed(errnoCode: errno)
        }
    }

    public func terminate() {
        let snapshot = currentProcessSnapshot(clearMaster: true)
        if let processID = snapshot.processID {
            kill(processID, SIGTERM)
        }
        if let masterFD = snapshot.masterFD {
            Darwin.close(masterFD)
        }
    }

    public func waitUntilExit() -> Int32 {
        exitSemaphore.wait()
        lock.lock()
        defer { lock.unlock() }
        return exitStatus ?? -1
    }

    private func readUntilExit(
        masterFD: Int32,
        processID: pid_t,
        onOutput: @escaping @Sendable (Data) -> Void
    ) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(masterFD, rawBuffer.baseAddress, rawBuffer.count)
            }
            if count > 0 {
                onOutput(Data(buffer.prefix(count)))
                continue
            }
            if count < 0, errno == EINTR {
                continue
            }
            break
        }
        closeMasterIfCurrent(masterFD)

        var status: Int32 = 0
        while waitpid(processID, &status, 0) < 0 {
            if errno == EINTR {
                continue
            }
            status = -1
            break
        }

        lock.lock()
        running = false
        exitStatus = status
        lock.unlock()
        exitSemaphore.signal()
    }

    private func currentMasterFD() throws -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        guard let masterFD else {
            throw LocalPTYProcessError.notStarted
        }
        return masterFD
    }

    private func currentProcessSnapshot(clearMaster: Bool) -> (masterFD: Int32?, processID: pid_t?) {
        lock.lock()
        let snapshot = (masterFD: masterFD, processID: processID)
        if clearMaster {
            masterFD = nil
        }
        lock.unlock()
        return snapshot
    }

    private func closeMasterIfCurrent(_ fd: Int32) {
        lock.lock()
        let shouldClose = masterFD == fd
        if shouldClose {
            masterFD = nil
        }
        lock.unlock()
        if shouldClose {
            Darwin.close(fd)
        }
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
