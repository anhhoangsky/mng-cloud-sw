#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Foundation

extension URLRequest {
    /// URLSession hands POST bodies to URLProtocol as a stream, so tests must
    /// read the captured request instead of assuming `httpBody` is populated.
    var capturedBody: Data? {
        if let httpBody {
            return httpBody
        }
        guard let stream = httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while true {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}
