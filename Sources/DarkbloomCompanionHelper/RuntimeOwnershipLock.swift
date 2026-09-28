import Darwin
import Foundation

public enum HelperOwnershipError: Error, Equatable, Sendable {
    case alreadyOwned
    case unsafePath
    case ioFailure
}

/// The file descriptor stays open for the lifetime of the helper. flock is
/// released by the kernel after a crash, unlike a stale PID file.
public final class RuntimeOwnershipLock: @unchecked Sendable {
    private let descriptor: Int32

    public init(url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var directoryInfo = stat()
        guard lstat(directory.path, &directoryInfo) == 0,
              (directoryInfo.st_mode & S_IFMT) == S_IFDIR,
              directoryInfo.st_uid == getuid(),
              directoryInfo.st_mode & 0o022 == 0 else { throw HelperOwnershipError.unsafePath }
        let fd = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw HelperOwnershipError.unsafePath }
        var fileInfo = stat()
        guard fstat(fd, &fileInfo) == 0,
              (fileInfo.st_mode & S_IFMT) == S_IFREG,
              fileInfo.st_uid == getuid(),
              fchmod(fd, 0o600) == 0 else {
            close(fd)
            throw HelperOwnershipError.unsafePath
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let reason = errno
            close(fd)
            throw reason == EWOULDBLOCK ? HelperOwnershipError.alreadyOwned : .ioFailure
        }
        descriptor = fd
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
