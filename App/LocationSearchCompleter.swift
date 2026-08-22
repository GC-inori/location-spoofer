import Combine
import Foundation
import MapKit

struct SearchSuggestionItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let rawCompletion: MKLocalSearchCompletion

    static func == (lhs: SearchSuggestionItem, rhs: SearchSuggestionItem) -> Bool {
        lhs.title == rhs.title && lhs.subtitle == rhs.subtitle
    }
}

final class LocationSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var queryText = ""
    @Published private(set) var suggestions: [SearchSuggestionItem] = []
    @Published private(set) var isSearching = false

    private let completer = MKLocalSearchCompleter()
    private var cancellables = Set<AnyCancellable>()
    private var resolveTask: Task<Void, Never>?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]

        $queryText
            .debounce(for: .milliseconds(180), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self else { return }
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    self.completer.cancel()
                    self.suggestions = []
                    self.isSearching = false
                } else {
                    self.isSearching = true
                    self.completer.queryFragment = trimmed
                }
            }
            .store(in: &cancellables)
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let maxCount = SearchConfigurationStore.shared.maxCountY
        let filtered = completer.results.prefix(maxCount).map { res in
            SearchSuggestionItem(
                title: res.title,
                subtitle: res.subtitle,
                rawCompletion: res
            )
        }
        DispatchQueue.main.async {
            self.suggestions = Array(filtered)
            self.isSearching = false
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isSearching = false
        }
    }

    func resolveCoordinate(
        for item: SearchSuggestionItem,
        completion: @escaping (CLLocationCoordinate2D?, String?) -> Void
    ) {
        resolveTask?.cancel()
        let request = MKLocalSearch.Request(completion: item.rawCompletion)
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                guard let mapItem = response?.mapItems.first else {
                    completion(nil, nil)
                    return
                }
                let coord = mapItem.placemark.coordinate
                let name = mapItem.name ?? item.title
                completion(coord, name)
            }
        }
    }

    func clear() {
        queryText = ""
        suggestions = []
        isSearching = false
        completer.cancel()
    }
}