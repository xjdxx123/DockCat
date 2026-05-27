import Foundation

extension URLSession {
    /// Performs a JSON GET request and returns a Result mapping HTTP/decoding outcomes to LLMUsageError.
    /// Providers use this to avoid duplicating the try/catch/status-check dance.
    func fetchJSON<T: Decodable>(
        _ request: URLRequest,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) async -> Result<T, LLMUsageError> {
        do {
            let (data, response) = try await self.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.http(status: -1, body: ""))
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return .failure(.http(status: http.statusCode, body: body))
            }
            do {
                return .success(try decoder.decode(T.self, from: data))
            } catch {
                return .failure(.decoding(underlying: error))
            }
        } catch let urlError as URLError {
            return .failure(.network(underlying: urlError))
        } catch {
            return .failure(.decoding(underlying: error))
        }
    }
}
