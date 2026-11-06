import Foundation

struct Stock: Identifiable, Hashable, Decodable {
    var id: String
    var name: String
    var kind: String
    var channel: String
    var targetPrint: String?
    var origin: String

    var isPaper: Bool { kind == "paper" }
    var isSlide: Bool { kind == "positive" }
    var isBlackAndWhite: Bool { channel == "bw" }
}

struct FilmCatalog {
    var films: [Stock]
    var papers: [Stock]

    static func load() throws -> FilmCatalog {
        guard let url = Bundle.main.url(forResource: "FilmCatalog", withExtension: "json") else {
            throw CatalogError.missing
        }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(File.self, from: data)
        return FilmCatalog(films: decoded.films, papers: decoded.papers)
    }

    func film(_ id: String) -> Stock? { films.first { $0.id == id } }
    func paper(_ id: String) -> Stock? { papers.first { $0.id == id } }

    var colorNegatives: [Stock] { films.filter { !$0.isSlide && !$0.isBlackAndWhite } }
    var slides: [Stock] { films.filter(\.isSlide) }
    var blackAndWhiteFilms: [Stock] { films.filter { $0.isBlackAndWhite && !$0.isPaper } }
    var colorPapers: [Stock] { papers.filter { !$0.isBlackAndWhite } }
    var blackAndWhitePapers: [Stock] { papers.filter(\.isBlackAndWhite) }

    private struct File: Decodable {
        var films: [Stock]
        var papers: [Stock]
    }
}

enum CatalogError: LocalizedError {
    case missing

    var errorDescription: String? {
        "安装包里没有目录 JSON。"
    }
}
