//
//  ViewController.swift
//  tca-coredata-example
//
//  Created by Daniel Williams on 4/26/22.
//

import UIKit
import Combine
import ComposableArchitecture
import CoreData

// MARK: - Models

typealias Snapshot = NSDiffableDataSourceSnapshot<AnyHashable, AnyHashable>

struct GridSnapshot: Equatable {
    
    let id = UUID()
    var value: Snapshot = .init()
    
    static func ==(lhs: GridSnapshot, rhs: GridSnapshot) -> Bool {
        return lhs.id == rhs.id
    }
}

struct GridItem: Equatable, Hashable {
    let id: UUID
    var topLeftIcon: UIImage?
    var topRightIcon: UIImage?
    var bottomLeftIcon: UIImage?
    var bottomRightIcon: UIImage?
    var thumbnail: UIImage?
}

// MARK: - State

struct GridState: Equatable {
    var currentSnapshot: GridSnapshot = .init()
}

// MARK: - Actions

enum GridAction {
    case insertDebugItems
    case observeSnapshots
    case didUpdateSnapshot(GridSnapshot)
}

// MARK: - Environment

final class CoreDataGridItemProvider: NSObject, NSFetchedResultsControllerDelegate {
    
    private(set) var fetchedResultsController: NSFetchedResultsController<Item>
    private let onSnapshotChanged = CurrentValueSubject<Snapshot, Never>(.init())

    override init() {
        
        let fetchRequest = Item.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Item.identifier, ascending: true)]
        let viewContext = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
        
        self.fetchedResultsController = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        
        super.init()
        
        fetchedResultsController.delegate = self
        try? fetchedResultsController.performFetch()
    }
    
    func insertDebugItems() {
        
        let context = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.newBackgroundContext()
        context.perform {
            for _ in 0..<100_000 {
                let item = Item(context: context)
                item.identifier = UUID()
            }
            
            try? context.save()
        }
    }
    
    func snapshotPublisher() -> AnyPublisher<Snapshot, Never> {
        
        onSnapshotChanged.eraseToAnyPublisher()
    }
    
    func gridItem(at indexPath: IndexPath) -> AnyPublisher<GridItem, Never> {
        
        // some test code to pretend that can uupdate grid items over time.
        // eg, thumbnail is loaded or updated,
        // or something in core data changes which causes one of the icons of the grid item to change.
        
        let item = fetchedResultsController.object(at: indexPath)
        
        let changeToMinusPublisher = Just(UIImage(systemName: "minus"))
            .delay(for: 1, scheduler: DispatchQueue.main)
            .map { GridItem(id: item.identifier!, thumbnail: $0) }
            .eraseToAnyPublisher()
        
        let changeToPlusPublisher = Just(UIImage(systemName: "plus"))
            .delay(for: 1, scheduler: DispatchQueue.main)
            .map { GridItem(id: item.identifier!, thumbnail: $0) }
            .eraseToAnyPublisher()
        
        return Just(GridItem(id: item.identifier!))
            .append(changeToPlusPublisher)
            .append(changeToMinusPublisher)
            .eraseToAnyPublisher()
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        
        onSnapshotChanged.send(snapshot as Snapshot)
    }
}

struct GridEnvironment {
    
    let itemProvider = CoreDataGridItemProvider()
}

extension GridEnvironment {
    
    static let prod = GridEnvironment()
}

// MARK: - Reducer

let gridReducer = Reducer<GridState, GridAction, GridEnvironment> { state, action, environment in
    switch action {
    case .insertDebugItems:
        return .fireAndForget {
            environment
                .itemProvider
                .insertDebugItems()
        }
    case .observeSnapshots:
        return environment
            .itemProvider
            .snapshotPublisher()
            .map(GridSnapshot.init)
            .map(GridAction.didUpdateSnapshot)
            .eraseToEffect()
        
    case .didUpdateSnapshot(let snapshot):
        state.currentSnapshot = snapshot
        return .none
    }
}
.debug()

class ViewController: UIViewController {
    
    private let store: Store<GridState, GridAction>
    private let viewStore: ViewStore<GridState, GridAction>
    private lazy var dataSource = makeDataSource()
    private lazy var layout = makeLayout()
    private var cellRegistration: UICollectionView.CellRegistration<GridCell, AnyHashable>!
    private var subscriptions: Set<AnyCancellable> = []
    
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()
    
    init(store: Store<GridState, GridAction>) {
        self.store = store
        self.viewStore = ViewStore(store)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setUpCollectionView()
        viewStore
            .publisher
            .currentSnapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.dataSource.apply($0.value, animatingDifferences: false)
            }
            .store(in: &subscriptions)
        
        viewStore.send(.observeSnapshots)
        viewStore.send(.insertDebugItems)
    }
    
    private func setUpCollectionView() {
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        collectionView.dataSource = dataSource
        collectionView.collectionViewLayout = layout
        cellRegistration = makeCellRegistration()
    }
    
    private func makeDataSource() -> UICollectionViewDiffableDataSource<AnyHashable, AnyHashable> {
        return .init(collectionView: collectionView) { [unowned self] collectionView, indexPath, itemIdentifier in
            collectionView.dequeueConfiguredReusableCell(
                using: self.cellRegistration,
                for: indexPath,
                item: itemIdentifier
            )
        }
    }
    
    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let oneThird = 1.0 / 3.0
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(oneThird),
                heightDimension: .fractionalHeight(1.0)
            )
        )
        item.contentInsets = .init(top: 1, leading: 1, bottom: 1, trailing: 1)
        
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .fractionalWidth(oneThird)
            ),
            subitems: [item]
        )
        
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 5
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10)

        return UICollectionViewCompositionalLayout(section: section)
    }
    
    private func makeCellRegistration() -> UICollectionView.CellRegistration<GridCell, AnyHashable> {
        let nib = UINib(nibName: String(describing: GridCell.self), bundle: nil)
        return .init(cellNib: nib) { cell, indexPath, itemIdentifier in
            
            // is there a better way to do this? What if nothing in the parent state is used in the child state?
            // we don't have a `\.gridCellStates`.
            let cellStore: Store<GridCellState, GridCellAction> = Store(
                initialState: .init(indexPath: indexPath),
                reducer: gridCellReducer,
                environment: .prod
            )
            
            cell.configure(with: cellStore)
        }
    }
}
