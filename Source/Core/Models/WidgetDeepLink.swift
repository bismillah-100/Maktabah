import Foundation

enum WidgetDeepLink: Equatable {
    case annotation(id: Int64)
    case history(bkId: Int, contentId: Int?)

    var url: URL {
        var components = URLComponents()
        components.scheme = "maktabah"
        switch self {
        case let .annotation(id):
            components.host = "annotation"
            components.queryItems = [URLQueryItem(name: "id", value: String(id))]
        case let .history(bkId, contentId):
            components.host = "history"
            var queryItems = [URLQueryItem(name: "bkId", value: String(bkId))]
            if let contentId {
                queryItems.append(URLQueryItem(name: "contentId", value: String(contentId)))
            }
            components.queryItems = queryItems
        }
        return components.url ?? URL(fileURLWithPath: "/")
    }

    static func parse(from url: URL) -> WidgetDeepLink? {
        guard url.scheme == "maktabah" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let host = url.host ?? components.host

        switch host {
        case "annotation":
            guard let idString = components.queryItems?.first(where: { $0.name == "id" })?.value,
                  let id = Int64(idString)
            else { return nil }
            return .annotation(id: id)

        case "history":
            guard let bkIdString = components.queryItems?.first(where: { $0.name == "bkId" })?.value,
                  let bkId = Int(bkIdString)
            else { return nil }
            let contentIdString = components.queryItems?.first(where: { $0.name == "contentId" })?.value
            return .history(bkId: bkId, contentId: contentIdString.flatMap(Int.init))

        default:
            return nil
        }
    }
}
