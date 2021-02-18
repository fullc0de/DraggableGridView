//
//  DraggableGridView.swift
//  DraggableGridView
//
//  Created by Heath Hwang on 2/8/21.
//

import SwiftUI

struct DraggableGridViewConfiguration {
    
    /// the number of column in a row
    var column: Int
    
    /// a space between items in horizontal
    var hSpace: CGFloat = 10.0
    
    /// a space between items in vertical
    var vSpace: CGFloat = 10.0
    
    /// a H/W ratio of each cell
    var cellRatio: CGFloat = 1.0
    
    /// This indicates whether to turn on dragging or not.
    var draggable: Bool = true
    
    /// a minimum time to press any item to trigger dragging.
    var pressDuration: Double = 0.3
    
    
    /// This calculates the width of an item cell based on the width of its container.
    /// - Parameter width: The width of its container.
    /// - Returns: The width of an item cell
    func cellWidth(width: CGFloat) -> CGFloat {
        return (width - (self.hSpace * CGFloat(self.column - 1))) / CGFloat(self.column)
    }
    
    /// This calculates the width of an item cell based on the width of its container and `cellRatio`.
    /// - Parameter width: The width of its container.
    /// - Returns: The width of an item cell
    func cellHeight(width: CGFloat) -> CGFloat {
        return self.cellWidth(width: width) * self.cellRatio
    }
}

struct DraggableGridView<Content: View, Item: Identifiable>: View {
    @State private var viewBounds: CGRect = .zero
    @State private var itemBoundsData: [ItemBoundsPreferencesData] = []
    @State private var expectedIndexes: [Item.ID: Int]
    
    @Binding var items: [Item]
    
    let config: DraggableGridViewConfiguration
    let content: (Item, Int, CGSize) -> Content
    
    @State private var dragState: DraggableGridViewDragState<Item.ID> = .inactive
    /// This indicates maximum containable bounds that items can be contained depending on the current view bounds.
    /// The number of it will be equal or greater than the number of items.
    ///  e.g) If config.column = `3`, the number of items = `4`, then the number of it is `6`
    @State private var availableItemBounds: [CGRect] = []
    
    fileprivate var onDragged: ((Int, Int) -> Void)? = nil
    
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .rigid)
    
    init(_ item: Binding<[Item]>,
         config: DraggableGridViewConfiguration = DraggableGridViewConfiguration(column: 3),
         @ViewBuilder content: @escaping (_ item: Item, _ index: Int, _ cellSize: CGSize) -> Content) {
        self._items = item
        self.config = config
        self.content = content
        var temp: [Item.ID: Int] = [:]
        item.wrappedValue.enumerated().forEach {
            temp[$0.element.id] = $0.offset
        }
        self._expectedIndexes = State(initialValue: temp)
    }
        
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // This fixer keeps ZStack's bounds still regardless of changing each item's position in it.
                self.alignFixer
                
                ForEach(self.items) { item in
                    self.content(item, self.items.firstIndex(where: { $0.id == item.id })!, self.cellSize(geo))
                        .frame(width: self.cellSize(geo).width, height: self.cellSize(geo).height)
                        //.border(Color.purple, width: 2)
                        .zIndex(self.isDragging(id: item.id) ? 1 : 0)
                        .alignmentGuide(.leading) { dimension in
                            -(dimension.width + self.config.hSpace) * CGFloat(self.expectedIndexOf(dataId: item.id) % self.config.column)
                        }
                        .alignmentGuide(.top) { dimension in
                            -(dimension.height + self.config.vSpace) * CGFloat(self.expectedIndexOf(dataId: item.id) / self.config.column)
                        }
                        .offset(x: self.isDragging(id: item.id) ? self.dragState.translation.width : 0,
                                y: self.isDragging(id: item.id) ? self.dragState.translation.height : 0)
                        .anchorPreference(key: ItemBoundsPreferencesKey.self,
                                          value: .bounds,
                                          transform: { [ItemBoundsPreferencesData(id: item.id, bound: geo[$0])] })
                        .gesture(LongPressGesture(minimumDuration: self.config.pressDuration)
                            .sequenced(before: DragGesture())
                            .onChanged { value in
                                switch value {
                                case .second(true, let drag):
                                    if let drag = drag {
                                        var draggedRect = self.itemBoundsData.first { $0.id == item.id as AnyHashable }?.bound ?? .zero
                                        draggedRect.origin.x += drag.translation.width
                                        draggedRect.origin.y += drag.translation.height
                                        
                                        var newState: DraggableGridViewDragState<Item.ID>!
                                        if self.dragState.translation == .zero {
                                            newState = .dragging(id: item.id, translation: drag.translation, delta: .zero, draggedRect: draggedRect)
                                        } else {
                                            let deltaX = drag.translation.width - self.dragState.translation.width
                                            let deltaY = drag.translation.height - self.dragState.translation.height
                                            newState = .dragging(id: item.id, translation: drag.translation, delta: CGPoint(x: deltaX, y: deltaY), draggedRect: draggedRect)
                                        }
                                        
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            self.dragState = newState
                                        }
                                    } else {
                                        self.hapticFeedback.impactOccurred()
                                        self.dragState = .dragging(id: item.id, translation: .zero, delta: .zero, draggedRect: .zero)
                                    }
                                default:
                                    self.dragState = .inactive
                                }
                            }
                            .onEnded { value in
                                switch value {
                                case .second(true, let drag):
                                    if let drag = drag {
                                        let currentIndex = self.actualIndexOf(dataId: self.dragState.id!)
                                        let newIndex = self.expectedIndexOfDraggedItem()
                                        
                                        self.items.insert(self.items.remove(at: currentIndex), at: newIndex)

                                        let dstRect = self.availableItemBounds[newIndex]
                                        var draggedRect = self.availableItemBounds[currentIndex]
                                        draggedRect.origin.x += drag.translation.width
                                        draggedRect.origin.y += drag.translation.height
                                        
                                        let remainedDistanceX = draggedRect.origin.x - dstRect.origin.x
                                        let remainedDistanceY = draggedRect.origin.y - dstRect.origin.y
                                        self.dragState = .dragging(id: item.id, translation: CGSize(width: remainedDistanceX, height: remainedDistanceY), delta: .zero, draggedRect: .zero)

                                        self.onDragged?(currentIndex, newIndex)
                                        
                                        withAnimation(.easeInOut(duration: 0.1)) {
                                            self.dragState = .inactive
                                        }
                                    }
                                default:
                                    self.dragState = .inactive
                                }
                        }, including: self.config.draggable ? .all : .none)
                }
            }
            .frame(width: geo.size.width, alignment: .topLeading)
            .background(DragViewBoundPreferenceSetter())
            .onPreferenceChange(ItemBoundsPreferencesKey.self) {
                self.itemBoundsData = $0
            }
//            // for debugging
//            .overlayPreferenceValue(ItemBoundsPreferencesKey.self) { bounds in
//                GeometryReader { geometry in
//                    ZStack(alignment: .topLeading) {
//                        ForEach(0..<bounds.count) { index in
//                            Text("(\(Int(bounds[index].bound.origin.x)), \(Int(bounds[index].bound.origin.y)))")
//                                .alignmentGuide(.top) { _ in -bounds[index].bound.origin.y }
//                                .alignmentGuide(.leading) { _ in -bounds[index].bound.origin.x }
//                                .offset(x: 10, y: bounds[index].bound.size.height)
//                                //.border(Color.red, width: 1.0)
//                        }
//                    }
//                    //.border(Color.blue, width: 2.0)
//                    Spacer()
//                }
//                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
//                //.border(Color.green, width: 1.0)
//            }
            
            Spacer()
            
//            // for debugging
//            Text("new position = \(self.expectedIndexOfDraggedItem())")
//                .offset(x: 0, y: -40)
//            Text("dragged rect(origin) = \(self.dragState.draggedRect.minX), \(self.dragState.draggedRect.minY)")
//                .offset(x: 0, y: -60)
//            Text("drag translation = \(self.dragState.translation.width), \(self.dragState.translation.height)")
//                .offset(x: 0, y: -80)
//            Text("drag delta = \(self.dragState.delta.x), \(self.dragState.delta.y)")
//                .offset(x: 0, y: -100)
        }
        .onPreferenceChange(DragViewBoundPreferenceKey.self) {
            if self.dragState.isDragging == false {
                if abs(self.viewBounds.height - $0.bounds.size.height) > 1.0 {
                    print("bounds = \($0.bounds)")
                    self.viewBounds = $0.bounds
                    self.updateFixedBounds()
                }
            }
        }
        .frame(height: viewBounds.size.height)
//        .overlay(
//            Color.clear
//                .border(Color.yellow, width: 2.0)
//                .frame(width: viewBounds.size.width, height: viewBounds.size.height)
//        )
        .onAppear{
            self.hapticFeedback.prepare()
        }
    }
    
    // MARK: - Private Methods
    private func cellSize(_ gp: GeometryProxy) -> CGSize {
        CGSize(width: config.cellWidth(width: gp.size.width), height: config.cellHeight(width: gp.size.width))
    }

    var alignFixer: some View {
        Color.clear
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
    
    private func actualIndexOf(dataId: Item.ID) -> Int {
        return items.firstIndex(where: { $0.id == dataId })!
    }
    
    private func expectedIndexOf(dataId: Item.ID) -> Int {
        let index = actualIndexOf(dataId: dataId)
        if let draggedId = dragState.id {
            let draggedSrcIndex = actualIndexOf(dataId: draggedId)
            let draggedDstIndex = expectedIndexOfDraggedItem()
            if index == draggedSrcIndex {
                return index
            } else {
                if draggedSrcIndex == draggedDstIndex {
                    return index
                } else if draggedSrcIndex > draggedDstIndex {
                    if index >= draggedDstIndex, index < draggedSrcIndex {
                        return index + 1
                    } else {
                        return index
                    }
                } else {
                    if index > draggedSrcIndex, index <= draggedDstIndex {
                        return index - 1
                    } else {
                        return index
                    }
                }
            }
        } else {
            return index
        }
    }
    
    private func isDragging(id: Item.ID) -> Bool {
        switch dragState {
        case .inactive:
            return false
        case .dragging(let draggedId, _, _, _):
            return draggedId == id
        }
    }
    
    private func expectedIndexOfDraggedItem() -> Int {
        let foundIndex = Array(0..<items.count).first { index in
            let targetBounds = self.availableItemBounds[index]
            return self.dragState.draggedRect.overlappedRate(overlappingRect: targetBounds) > 0.7
        }
        if let index = foundIndex {
            return index
        } else if let id = dragState.id {
            return actualIndexOf(dataId: id)
        } else {
            return 0
        }
    }
    
    private func updateFixedBounds() {
        let viewWidth = self.viewBounds.size.width
        let cellWidth = self.config.cellWidth(width: viewWidth)
        let cellHeight = self.config.cellHeight(width: viewWidth)
        let rowCount = (items.count / config.column) + 1
        
        
        self.availableItemBounds = Array(0..<(rowCount * config.column)).map {
            CGRect(x: (cellWidth + self.config.hSpace) * CGFloat($0 % self.config.column),
                   y: (cellHeight + self.config.vSpace) * CGFloat($0 / self.config.column),
                   width: cellWidth,
                   height: cellHeight)
        }
    }
}

extension DraggableGridView {
    public func onDrag(perform action: ((Int, Int) -> Void)? = nil) -> DraggableGridView {
        var view = self
        view.onDragged = action
        return view
    }
}

extension CGRect {
    fileprivate func overlappedRate(overlappingRect: CGRect) -> CGFloat {
        let volume = self.width * self.height
        let intersect = self.intersection(overlappingRect)
        if intersect.isNull {
            return 0.0
        }
        return (intersect.width * intersect.height) / volume
    }
}

enum DraggableGridViewDragState<ID> {
    case inactive
    case dragging(id: ID, translation: CGSize, delta: CGPoint, draggedRect: CGRect)
    
    var isDragging: Bool {
        switch self {
        case .inactive:
            return false
        case .dragging:
            return true
        }
    }
    
    var id: ID? {
        switch self {
        case .inactive:
            return nil
        case .dragging(let id, _, _, _):
            return id
        }
    }
    
    var translation: CGSize {
        switch self {
        case .inactive:
            return .zero
        case .dragging(_, let translation, _, _):
            return translation
        }
    }
    
    var delta: CGPoint {
        switch self {
        case .inactive:
            return .zero
        case .dragging(_, _, let delta, _):
            return delta
        }
    }
    
    var draggedRect: CGRect {
        switch self {
        case .inactive:
            return .zero
        case .dragging(_, _, _, let rect):
            return rect
        }
    }
}

private struct ItemBoundsPreferencesData: Identifiable, Equatable {
    let id: AnyHashable
    let bound: CGRect
}

private struct ItemBoundsPreferencesKey: PreferenceKey {
    public static var defaultValue: [ItemBoundsPreferencesData] = []
    
    public static func reduce(value: inout [ItemBoundsPreferencesData], nextValue: () -> [ItemBoundsPreferencesData]) {
        value.append(contentsOf: nextValue())
    }
}

private struct BoundsData: Equatable {
    var bounds: CGRect = .zero
    
    static func ==(lhs: BoundsData, rhs: BoundsData) -> Bool {
        return lhs.bounds == rhs.bounds
    }
}

private struct DragViewBoundPreferenceKey: PreferenceKey {
    static let defaultValue: BoundsData = BoundsData()

    static func reduce(value: inout BoundsData, nextValue: () -> BoundsData) {
        let data = nextValue()
        var newBounds = value.bounds
        newBounds.origin.x += data.bounds.origin.x
        newBounds.origin.y += data.bounds.origin.y
        newBounds.size.width += data.bounds.size.width
        newBounds.size.height += data.bounds.size.height
        value.bounds = newBounds
    }
}

private struct DragViewBoundPreferenceSetter: View {
    var body: some View {
        GeometryReader { geometry in
            return Color.clear.anchorPreference(key: DragViewBoundPreferenceKey.self, value: .bounds, transform: { BoundsData(bounds: geometry[$0]) })
        }
    }
}

private struct OverlayView: View {
    private let image: UIImage
    
    init(image: UIImage) {
        self.image = image
    }
    
    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
}

struct TestImageItem: Identifiable {
    let id: Int
    let image: UIImage
}

struct PreviewBaseView: View {
    @State var images: [TestImageItem] = [
        TestImageItem(id: 0, image: #imageLiteral(resourceName: "img_twice_51")),
        TestImageItem(id: 1, image: #imageLiteral(resourceName: "img_twice_52")),
        TestImageItem(id: 2, image: #imageLiteral(resourceName: "img_twice_53")),
        TestImageItem(id: 3, image: #imageLiteral(resourceName: "img_twice_54")),
        TestImageItem(id: 4, image: #imageLiteral(resourceName: "img_twice_55")),
        TestImageItem(id: 5, image: #imageLiteral(resourceName: "img_twice_50"))
    ]
    @State var selectedIndex: Int? = nil

    private var gridConfig: DraggableGridViewConfiguration {
        DraggableGridViewConfiguration(column: 3, hSpace: 10, vSpace: 10)
    }
    
    var body: some View {
        VStack {
            DraggableGridView($images, config: gridConfig) { item, index, size in
                OverlayView(image: item.image)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
            .padding(.bottom, 40)
            Text("grid count = \(images.count)")
            Text("order(id) = \(images.map { "\($0.id)" }.joined(separator: ","))")
        }
    }
}

struct ButtonGridView_Previews: PreviewProvider {
    
    static var previews: some View {
        PreviewBaseView()
    }
}

