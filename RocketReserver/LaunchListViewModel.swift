import Apollo
import ApolloPagination
import Combine
import RocketReserverAPI
import SwiftUI

class LaunchListViewModel: ObservableObject {
    @Published var launches: [LaunchListQuery.Data.Launches.Launch]

    @Published var isLoading: Bool = false
    @Published var hasMore: Bool = true

    @Published var errorString: String = ""

    private var cancellable: AnyCancellable?
    private let pageSize = 10
    private var pager: GraphQLQueryPager<PaginationOutput<LaunchListQuery, LaunchListQuery>>?

    init() {
        launches = []
        setUpPaginaiton()
    }

    // MARK: - Launch Loading

    private func setUpPaginaiton() {
        let initialQueury = LaunchListQuery(
            pageSize: .some(pageSize),
            cursor: .none
        )
        pager = GraphQLQueryPager(
            client: Network.shared.apollo,
            initialQuery: initialQueury,
            extractPageInfo: { [weak self] data in
                DispatchQueue.main.async {
                    self?.hasMore = data.launches.hasMore
                }
                print("cursor: data.launches: \(data.launches.launches.compactMap { $0?.mission?.name })")
                return CursorBasedPagination.Forward(hasNext: data.launches.hasMore, endCursor: data.launches.cursor)
            },
            pageResolver: { [weak self] page, paginationDirection in
                guard let self else {
                    return nil
                }

                print("cursor: page.endCursor: \(page.endCursor)")

                switch paginationDirection {
                case .next:
                    return LaunchListQuery(pageSize: .some(self.pageSize), cursor: page.endCursor ?? .none)
                case .previous:
                    return nil
                }
            }
        )

        cancellable = pager?.receive(on: DispatchQueue.main).sink { result in
            switch result {
            case let .success(data):
                let (output, source) = data
                let initial = output.initialPage.launches.launches.compactMap { $0 }
                let next = output.nextPages.map { page in
                    page.launches.launches.compactMap { $0 }
                }.flatMap { $0 }

                print("data source is: \(source)")
                self.launches = initial + next

            case let .failure(error):
                print("skipping error: \(error)")
            }
            self.isLoading = false
        }
    }

    func reset() async {
        await MainActor.run {
            launches = []
            isLoading = false
            hasMore = true
        }
        await loadMoreLaunchesIfTheyExist()
    }

    func loadMoreLaunchesIfTheyExist() async {
        guard !isLoading, hasMore else {
            return
        }
        await MainActor.run {
            isLoading = true
        }

        if launches.isEmpty {
            pager?.fetch()
        } else {
            pager?.loadNext(completion: { [weak self] (error: PaginationError?) in
                guard let self else {
                    return
                }
                if let error {
                    errorString = error.localizedDescription
                }
            })
        }
    }

    deinit {
        cancellable = nil
    }
}
