import Foundation
import Testing

@testable import SuperscribeKit

@Suite("HTTPValidation", .serialized, ResetSharedStateTrait())
struct HTTPValidationTests {
    @Test func isSuccessFor2xx() throws -> Void {
        let ok =
            (try #require(
                HTTPURLResponse(
                    url: (try TestHelpers.requireValue(URL(string: "https://example.com"))),
                    statusCode: 204,
                    httpVersion: nil,
                    headerFields: nil
                )))
        #expect(ok.isSuccess == true)
    }

    @Test func isSuccessFalseFor404() throws -> Void {
        let missing =
            (try #require(
                HTTPURLResponse(
                    url: (try TestHelpers.requireValue(URL(string: "https://example.com/missing"))),
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: nil
                )))
        #expect(missing.isSuccess == false)
    }

    @Test func requireSuccessAccepts2xx() throws -> Void {
        let response =
            (try #require(
                HTTPURLResponse(
                    url: (try TestHelpers.requireValue(URL(string: "https://example.com"))),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )))
        try HTTPValidation.requireSuccess(response, url: (try #require(URL(string: "https://example.com"))))
    }

    @Test func requireSuccessIgnoresNonHTTP() throws -> Void {
        let response = URLResponse(
            url: (try #require(URL(string: "file:///tmp/x"))),
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        )
        try HTTPValidation.requireSuccess(response, url: (try #require(URL(string: "file:///tmp/x"))))
    }

    @Test func requireSuccessThrowsForHTTPError() throws -> Void {
        let response =
            (try #require(
                HTTPURLResponse(
                    url: (try TestHelpers.requireValue(URL(string: "https://example.com"))),
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )))
        #expect(throws: ModelInstallationError.self) {
            try HTTPValidation.requireSuccess(response, url: (try #require(URL(string: "https://example.com"))))
        }
    }
}
