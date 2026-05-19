import Foundation
import Testing

@testable import SuperscribeKit

@Suite("HTTPValidation")
struct HTTPValidationTests {
    @Test func isSuccessFor2xx() {
        let ok = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!
        #expect(ok.isSuccess == true)
    }

    @Test func isSuccessFalseFor404() {
        let missing = HTTPURLResponse(
            url: URL(string: "https://example.com/missing")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!
        #expect(missing.isSuccess == false)
    }

    @Test func requireSuccessAccepts2xx() throws {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        try HTTPValidation.requireSuccess(response, url: URL(string: "https://example.com")!)
    }

    @Test func requireSuccessIgnoresNonHTTP() throws {
        let response = URLResponse(
            url: URL(string: "file:///tmp/x")!,
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        )
        try HTTPValidation.requireSuccess(response, url: URL(string: "file:///tmp/x")!)
    }

    @Test func requireSuccessThrowsForHTTPError() {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!
        #expect(throws: ModelInstallationError.self) {
            try HTTPValidation.requireSuccess(response, url: URL(string: "https://example.com")!)
        }
    }
}
