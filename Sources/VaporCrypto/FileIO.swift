import Crypto
import FoundationEssentials
import _NIOFileSystem
import _NIOFileSystemFoundationCompat
import NIOCore
import NIOHTTP1
import NIOPosix
import VaporHTTP

extension FileIO {
    /// Generates a fresh ETag for a file or returns its currently cached one.
    /// - Parameters:
    ///   - path: The file's path.
    ///   - lastModified: When the file was last modified.
    /// - Returns: A `String` which holds the ETag.
    private func generateETagHash(path: String, lastModified: Date) async throws -> String {
        if let hash = request.application.storage[FileMiddleware.ETagHashes.self]?[path], hash.lastModified == lastModified {
            return hash.digestHex
        } else {
            return try await FileSystem.shared.withFileHandle(forReadingAt: .init(path)) { handle in
                let buffer = try await handle.readToEnd(maximumSizeAllowed: .bytes(.max))
                let digest = SHA256.hash(data: buffer.readableBytesView)

                // update hash in dictionary
                request.application.storage[FileMiddleware.ETagHashes.self]?[path] = FileMiddleware.ETagHashes.FileHash(lastModified: lastModified, digestHex: digest.hex)

                return digest.hex
            }
        }
    }
}

extension FileIO {
    /// Generates a chunked `Response` for the specified file. This method respects values in
    /// the `"ETag"` header and is capable of responding `304 Not Modified` if the file in question
    /// has not been modified since last served. If `advancedETagComparison` is set to true,
    /// the response will have its ETag field set to a byte-by-byte hash of the requested file. If set to false, a simple ETag consisting of the last modified date and file size
    /// will be used. This method will also set the `"Content-Type"` header
    /// automatically if an appropriate `MediaType` can be found for the file's suffix.
    ///
    ///     app.get("file-stream") { req in
    ///         return req.fileio.streamFile(at: "/path/to/file.txt")
    ///     }
    ///
    /// - parameters:
    ///     - path: Path to file on the disk.
    ///     - chunkSize: Maximum size for the file data chunks.
    ///     - mediaType: HTTPMediaType, if not specified, will be created from file extension.
    ///     - advancedETagComparison: The method used when ETags are generated. If true, a byte-by-byte hash is created (and cached), otherwise a simple comparison based on the file's last modified date and size.
    ///     - onCompleted: Closure to be run on completion of stream.
    /// - returns: A `200 OK` response containing the file stream and appropriate headers.
    public func streamFile(
        at path: String,
        chunkSize: Int = NonBlockingFileIO.defaultChunkSize,
        mediaType: HTTPMediaType? = nil,
        advancedETagComparison: Bool,
        onCompleted: @escaping @Sendable (Result<Void, Error>) -> () = { _ in }
    ) -> EventLoopFuture<Response> {
        // Get file attributes for this file.
        self.request.eventLoop.makeFutureWithTask {
            try await self.asyncStreamFile(at: path, chunkSize: chunkSize, mediaType: mediaType, advancedETagComparison: advancedETagComparison, onCompleted: onCompleted)
        }
    }
}

extension FileIO {
    /// Generates a chunked `Response` for the specified file. This method respects values in
    /// the `"ETag"` header and is capable of responding `304 Not Modified` if the file in question
    /// has not been modified since last served. If `advancedETagComparison` is set to true,
    /// the response will have its ETag field set to a byte-by-byte hash of the requested file. If set to false, a simple ETag consisting of the last modified date and file size
    /// will be used. This method will also set the `"Content-Type"` header
    /// automatically if an appropriate `MediaType` can be found for the file's suffix.
    ///
    ///     app.get("file-stream") { req in
    ///         return req.fileio.asyncStreamFile(at: "/path/to/file.txt")
    ///     }
    ///
    /// Async equivalent of ``streamFile(at:chunkSize:mediaType:advancedETagComparison:onCompleted:)`` using Swift Concurrency
    /// functions under the hood
    ///
    /// - parameters:
    ///     - path: Path to file on the disk.
    ///     - chunkSize: Maximum size for the file data chunks.
    ///     - mediaType: HTTPMediaType, if not specified, will be created from file extension.
    ///     - advancedETagComparison: The method used when ETags are generated. If true, a byte-by-byte hash is created (and cached), otherwise a simple comparison based on the file's last modified date and size.
    ///     - onCompleted: Closure to be run on completion of stream.
    /// - returns: A `200 OK` response containing the file stream and appropriate headers.
    public func asyncStreamFile(
        at path: String,
        chunkSize: Int = NonBlockingFileIO.defaultChunkSize,
        mediaType: HTTPMediaType? = nil,
        advancedETagComparison: Bool = false,
        onCompleted: @escaping @Sendable (Result<Void, Error>) async throws -> () = { _ in }
    ) async throws -> Response {
        // Get file attributes for this file.
        guard let fileInfo = try await FileSystem.shared.info(forFileAt: .init(path)) else {
            throw Abort(.internalServerError)
        }

        let contentRange: HTTPHeaders.Range?
        if let rangeFromHeaders = request.headers.range {
            if rangeFromHeaders.unit == .bytes && rangeFromHeaders.ranges.count == 1 {
                contentRange = rangeFromHeaders
            } else {
                contentRange = nil
            }
        } else if request.headers.contains(name: .range) {
            // Range header was supplied but could not be parsed i.e. it was invalid
            request.logger.debug("Range header was provided in request but was invalid")
            throw Abort(.badRequest)
        } else {
            contentRange = nil
        }

        let eTag: String

        if advancedETagComparison {
            eTag = try await generateETagHash(path: path, lastModified: fileInfo.lastDataModificationTime.date)
        } else {
            // Generate ETag value, "last modified date in epoch time" + "-" + "file size"
            eTag = "\"\(fileInfo.lastDataModificationTime.seconds)-\(fileInfo.size)\""
        }
        
        // Create empty headers array.
        var headers: HTTPHeaders = [:]

        // Respond with lastModified header
        headers.lastModified = HTTPHeaders.LastModified(value: fileInfo.lastDataModificationTime.date)

        headers.replaceOrAdd(name: .eTag, value: eTag)

        // Check if file has been cached already and return NotModified response if the etags match
        if eTag == request.headers.first(name: .ifNoneMatch) {
            // Per RFC 9110 here: https://www.rfc-editor.org/rfc/rfc9110.html#status.304
            // and here: https://www.rfc-editor.org/rfc/rfc9110.html#name-content-encoding
            // A 304 response MUST include the ETag header and a Content-Length header matching what the original resource's content length would have been were this a 200 response.
            headers.replaceOrAdd(name: .contentLength, value: fileInfo.size.description)
            return Response(status: .notModified, version: .http1_1, headersNoUpdate: headers, body: .empty)
        }

        // Create the HTTP response.
        let response = Response(status: .ok, headers: headers)
        let offset: Int64
        let byteCount: Int
        if let contentRange = contentRange {
            response.status = .partialContent
            response.headers.add(name: .accept, value: contentRange.unit.serialize())
            if let firstRange = contentRange.ranges.first {
                do {
                    let range = try firstRange.asResponseContentRange(limit: Int(fileInfo.size))
                    response.headers.contentRange = HTTPHeaders.ContentRange(unit: contentRange.unit, range: range)
                    (offset, byteCount) = try firstRange.asByteBufferBounds(withMaxSize: Int(fileInfo.size), logger: request.logger)
                } catch {
                    throw Abort(.badRequest)
                }
            } else {
                offset = 0
                byteCount = Int(fileInfo.size)
            }
        } else {
            offset = 0
            byteCount = Int(fileInfo.size)
        }
        // Set Content-Type header based on the media type
        // Only set Content-Type if file not modified and returned above.
        if
            let fileExtension = path.components(separatedBy: ".").last,
            let type = mediaType ?? HTTPMediaType.fileExtension(fileExtension)
        {
            response.headers.contentType = type
        }
        
        response.body = .init(asyncStream: { stream in
            do {
                let chunks = try await self.readFile(at: path, chunkSize: chunkSize, offset: offset, byteCount: byteCount)
                do {
                    for try await chunk in chunks {
                        try await stream.writeBuffer(chunk)
                    }
                    try? await chunks.closeHandle()
                } catch {
                    try? await chunks.closeHandle()
                    throw error
                }
                try await stream.write(.end)
                try await onCompleted(.success(()))
            } catch {
                try? await stream.write(.error(error))
                try await onCompleted(.failure(error))
            }
        }, count: byteCount, byteBufferAllocator: request.byteBufferAllocator)

        return response
    }
}