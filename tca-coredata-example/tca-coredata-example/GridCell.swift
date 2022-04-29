//
//  GridCell.swift
//  tca-coredata-example
//
//  Created by Daniel Williams on 4/28/22.
//

import Foundation
import UIKit
import Combine
import ComposableArchitecture

struct GridCellState: Equatable {
    let indexPath: IndexPath
    var gridItem: GridItem?
}

enum GridCellAction {
    case loadItem(at: IndexPath)
    case didUpdateGridItem(GridItem)
}

let gridCellReducer = Reducer<GridCellState, GridCellAction, GridEnvironment> { state, action, environment in
    switch action {
    case .loadItem(let indexPath):
        return environment
            .itemProvider
            .gridItem(at: indexPath)
            .map(GridCellAction.didUpdateGridItem)
            .eraseToEffect()
    
    case .didUpdateGridItem(let gridItem):
        state.gridItem = gridItem
        return .none
    }
}

final class GridCell: UICollectionViewCell {
    
    private var store: Store<GridCellState, GridCellAction>?
    private var viewStore: ViewStore<GridCellState, GridCellAction>?
    private var subscriptions = Set<AnyCancellable>()
    
    @IBOutlet private weak var topLeftIcon: UIImageView!
    @IBOutlet private weak var topRightIcon: UIImageView!
    @IBOutlet private weak var bottomLeftIcon: UIImageView!
    @IBOutlet private weak var bottomRightIcon: UIImageView!
    @IBOutlet private weak var thumbnail: UIImageView!
    
    override func prepareForReuse() {
        super.prepareForReuse()
        store = nil
        viewStore = nil
        thumbnail.image = nil
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
    }
    
    func configure(with store: Store<GridCellState, GridCellAction>) {
        backgroundColor = .green
        
        let viewStore = ViewStore(store)
        self.store = store
        self.viewStore = viewStore
        viewStore.send(.loadItem(at: viewStore.indexPath))
        
        viewStore.publisher
            .gridItem
            .sink { [weak self] in
                self?.topLeftIcon.image = $0?.topLeftIcon
                self?.topRightIcon.image = $0?.topRightIcon
                self?.bottomLeftIcon.image = $0?.bottomLeftIcon
                self?.bottomRightIcon.image = $0?.bottomRightIcon
                self?.thumbnail.image = $0?.thumbnail
            }
            .store(in: &subscriptions)
    }
}
