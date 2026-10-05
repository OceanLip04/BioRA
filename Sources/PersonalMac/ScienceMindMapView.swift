import PersonalCore
import SwiftUI

/// Native, keyboard-reachable nodes over a Canvas that draws only the noninteractive connectors.
struct ScienceMindMapView: View {
    let question: ScientificQuestion
    let language: AppLanguage
    let canEdit: Bool
    let canMoveNodes: Bool
    let experimentName: (UUID) -> String
    let moveNode: (UUID, ScienceGraphPoint) -> Bool
    let resetLayout: () -> Void
    let addClaim: () -> Void
    let addAtom: () -> Void
    let editQuestion: () -> Void
    let editClaim: (UUID) -> Void
    let editAtom: (UUID) -> Void
    let linkClaim: (UUID) -> Void
    let linkAtom: (UUID) -> Void
    var canvasHeight: CGFloat = 550
    var fitsAvailableHeight = false
    var layoutOverride: ScienceGraphLayout? = nil
    var titleOverride: String? = nil
    var summaryOverride: String? = nil
    var offersFullScreen = true
    @Environment(\.knowledgeTreeFitRevision) private var fullScreenFitRevision
    @StateObject private var fullScreenWindow = KnowledgeTreeWindow()
    @State private var scale = 0.8
    @State private var selectedID: UUID?
    @State private var hoveredID: UUID?
    @State private var dragOffsets: [UUID: CGSize] = [:]
    @State private var pendingDrops: [UUID: ScienceGraphPoint] = [:]
    @State private var viewportSize: CGSize = CGSize(width: 900, height: 550)
    @State private var pan: CGSize = .zero
    @State private var dragStartPan: CGSize?
    @State private var pinchStartScale: CGFloat?
    @State private var initiallyFitted = false
    @State private var cachedLayout: ScienceGraphLayout?
    @State private var showEvidence = true
    @State private var pointerInsideCanvas = false

    // Zoom and pan change view state many times per second. Rebuild the graph only when its data changes.
    private var layout: ScienceGraphLayout {
        let full = layoutOverride ?? cachedLayout ?? ScienceGraphLayout(question: question, language: language)
        return !showEvidence && !question.mainline.isEmpty ? full.mainlineOnly() : full
    }
    private var selectedNode: ScienceGraphNode? { layout.nodes.first { $0.id == selectedID } }
    private func wording(_ chinese: String, _ english: String) -> String { language == .english ? english : chinese }
    private var focusID: UUID? { hoveredID ?? selectedID }
    private func relatedIDs(_ map: ScienceGraphLayout) -> Set<UUID> {
        guard let focusID else { return [] }
        var result: Set<UUID> = [focusID]
        for edge in map.edges where edge.fromID == focusID || edge.toID == focusID {
            result.insert(edge.fromID); result.insert(edge.toID)
        }
        // Highlight the whole supporting tree, not merely a result's immediate children.
        var queue = [focusID], cursor = 0, visited: Set<UUID> = [focusID]
        while cursor < queue.count {
            let id = queue[cursor]; cursor += 1
            for edge in map.edges where edge.toID == id && edge.kind != .progression {
                result.insert(edge.fromID)
                if visited.insert(edge.fromID).inserted { queue.append(edge.fromID) }
            }
        }
        return result
    }
    private func fit(_ map: ScienceGraphLayout) {
        let target = min((viewportSize.width - 32) / map.width, (viewportSize.height - 32) / map.height)
        scale = min(3, max(0.05, target))
        pan = boundedPan(CGSize(width: (viewportSize.width - map.width * scale) / 2,
                                height: (viewportSize.height - map.height * scale) / 2), map: map, zoom: scale)
    }

    private func boundedPan(_ proposed: CGSize, map: ScienceGraphLayout, zoom: CGFloat) -> CGSize {
        func axis(_ value: CGFloat, content: CGFloat, viewport: CGFloat) -> CGFloat {
            // Keep part of the map visible while permitting movement even when it fits.
            let visibleEdge: CGFloat = 80
            return min(viewport - visibleEdge, max(visibleEdge - content, value))
        }
        return CGSize(width: axis(proposed.width, content: map.width * zoom, viewport: viewportSize.width),
                      height: axis(proposed.height, content: map.height * zoom, viewport: viewportSize.height))
    }

    private func zoom(to proposed: CGFloat, map: ScienceGraphLayout,
                      anchor: CGPoint? = nil, animated: Bool = false) {
        let next = min(3, max(0.05, proposed))
        guard next != scale else { return }
        let center = anchor ?? CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let ratio = next / scale
        let nextPan = boundedPan(CGSize(width: center.x - (center.x - pan.width) * ratio,
                                       height: center.y - (center.y - pan.height) * ratio), map: map, zoom: next)
        if animated {
            withAnimation(.easeOut(duration: 0.18)) { pan = nextPan; scale = next }
        } else {
            pan = nextPan; scale = next
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: layoutOverride == nil ? "RESEARCH MAP" : "FIGURE LOGIC")
                    Text(titleOverride ?? wording("研究主线与结论树", "Research mainline & conclusion trees")).font(EditorialType.title(24))
                }
                Spacer()
                if offersFullScreen {
                    Button(wording("全屏", "Full screen"), systemImage: "arrow.up.left.and.arrow.down.right") {
                        fullScreenWindow.present(title: fullScreenTitle, languageIsEnglish: language == .english, content: AnyView(fullScreenMap))
                    }.buttonStyle(QuietButtonStyle())
                        .help(wording("在独立全屏画布中查看知识树", "Open the knowledge tree in a native full-screen canvas"))
                }
                if !question.mainline.isEmpty {
                    Button(wording(showEvidence ? "仅看主线" : "展开结论树", showEvidence ? "Mainline only" : "Show conclusion trees")) {
                        showEvidence.toggle(); selectedID = nil; hoveredID = nil; fit(layout)
                    }.buttonStyle(.plain)
                }
                if canEdit {
                    Button("原子实验", systemImage: "plus", action: addAtom).buttonStyle(QuietButtonStyle())
                    Button("论断", systemImage: "plus", action: addClaim).buttonStyle(QuietButtonStyle())
                } else {
                    Text(wording("内容只读", "Read-only content")).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }.padding(18)
            Rectangle().fill(Palette.line).frame(height: 0.5)
            HStack(spacing: 9) {
                if let summaryOverride { Text(summaryOverride) }
                else {
                    Label(wording("\(question.atomicExperiments.count) 个原子实验", "\(question.atomicExperiments.count) atomic experiments"), systemImage: "flask")
                    Text(wording("· \(question.claims.count) 条论断 · \(question.evidenceLinks.count + question.relations.count) 条证据关系", "· \(question.claims.count) claims · \(question.evidenceLinks.count + question.relations.count) evidence links"))
                }
                Spacer()
                if canMoveNodes {
                    Button("自动排列", systemImage: "arrow.triangle.2.circlepath", action: resetLayout)
                        .buttonStyle(.plain).disabled(question.graphPositions.isEmpty).help("清除手动节点位置并重新排列")
                }
                Button { withAnimation(.easeOut(duration: 0.22)) { fit(layout) } } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 30, height: 30).contentShape(Rectangle())
                }
                    .buttonStyle(.plain).accessibilityLabel(wording("适合窗口", "Fit to Window"))
                    .help(wording("将图谱缩放至当前窗口", "Fit the graph to the current window"))
                Button { zoom(to: scale / 1.2, map: layout, animated: true) } label: {
                    Image(systemName: "minus.magnifyingglass").frame(width: 30, height: 30).contentShape(Rectangle())
                }
                    .buttonStyle(.plain).accessibilityLabel(wording("缩小图谱", "Zoom out"))
                    .help(wording("缩小图谱（⌘−）", "Zoom out (⌘−)"))
                Text("\(Int((scale * 100).rounded()))%").monospacedDigit().frame(width: 42)
                    .help(wording("按住 ⌘ 并滚动鼠标缩放图谱", "Hold ⌘ and scroll to zoom the map"))
                Button { zoom(to: scale * 1.2, map: layout, animated: true) } label: {
                    Image(systemName: "plus.magnifyingglass").frame(width: 30, height: 30).contentShape(Rectangle())
                }
                    .buttonStyle(.plain).accessibilityLabel(wording("放大图谱", "Zoom in"))
                    .help(wording("放大图谱（⌘＋）", "Zoom in (⌘+)"))
            }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                .padding(.horizontal, 18).frame(height: 43)
                // A real hit target behind the controls prevents clipped nodes from receiving
                // the same click when they have been panned underneath this toolbar.
                .background {
                    Button {} label: { Palette.surface.contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityHidden(true)
                }
                .zIndex(10)
            Rectangle().fill(Palette.line).frame(height: 0.5)
            HStack(spacing: 0) {
                GeometryReader { geometry in
                    let map = layout
                    ZStack(alignment: .topLeading) {
                        Button {
                            selectedID = nil
                            hoveredID = nil
                        } label: {
                            Rectangle().fill(.clear).contentShape(Rectangle())
                        }
                            .buttonStyle(.plain)
                            .accessibilityLabel(wording("关闭节点详情", "Close node details"))
                            .accessibilityHidden(selectedID == nil)
                            .highPriorityGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("scienceMapViewport"))
                                .onChanged { value in
                                    if dragStartPan == nil { dragStartPan = pan }
                                    let start = dragStartPan ?? pan
                                    pan = boundedPan(CGSize(width: start.width + value.translation.width,
                                                            height: start.height + value.translation.height), map: map, zoom: scale)
                                }
                                .onEnded { _ in dragStartPan = nil })
                        graphPlane(map)
                            .frame(width: map.width, height: map.height)
                            .scaleEffect(scale, anchor: .topLeading)
                            .offset(pan)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    .coordinateSpace(name: "scienceMapViewport")
                    .clipped()
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active: pointerInsideCanvas = true
                        case .ended: pointerInsideCanvas = false
                        }
                    }
                    .background(ScienceMapInputMonitor(
                        pointerInsideCanvas: pointerInsideCanvas,
                        scrollToPan: { delta in
                            guard dragStartPan == nil, dragOffsets.isEmpty else { return }
                            pan = boundedPan(CGSize(width: pan.width + delta.width,
                                                    height: pan.height + delta.height), map: map, zoom: scale)
                        },
                        scrollToZoom: { factor, point, precise in
                            zoom(to: scale * factor, map: map, anchor: point, animated: !precise)
                        },
                        keyZoom: { direction, isRepeat in
                            zoom(to: direction > 0 ? scale * 1.2 : scale / 1.2, map: map, animated: !isRepeat)
                        }).frame(width: geometry.size.width, height: geometry.size.height))
                    .simultaneousGesture(MagnifyGesture()
                        .onChanged { value in
                            if pinchStartScale == nil { pinchStartScale = scale }
                            zoom(to: (pinchStartScale ?? scale) * value.magnification, map: map)
                        }
                        .onEnded { _ in pinchStartScale = nil })
                    .onAppear {
                        cachedLayout = ScienceGraphLayout(question: question, language: language)
                        viewportSize = geometry.size
                        if !initiallyFitted {
                            fit(layout)
                            initiallyFitted = true
                        }
                    }
                    .onChange(of: geometry.size) { _, size in
                        viewportSize = size
                        pan = boundedPan(pan, map: layout, zoom: scale)
                    }
                    .onChange(of: fullScreenFitRevision) { _, _ in
                        viewportSize = geometry.size
                        fit(layout)
                    }
                }
                .background(Palette.canvas.opacity(0.58))
                if let node = selectedNode {
                    Rectangle().fill(Palette.line).frame(width: 0.5)
                    inspector(node).frame(width: 254).frame(maxHeight: .infinity, alignment: .top)
                        .background(Palette.surface)
                }
            }.frame(height: fitsAvailableHeight ? nil : canvasHeight)
                .frame(maxHeight: fitsAvailableHeight ? .infinity : nil)
            Rectangle().fill(Palette.line).frame(height: 0.5)
            HStack(spacing: 16) {
                if !question.mainline.isEmpty { legend(wording("研究推进（非证明）", "Research progression (not proof)"), color: Palette.accent) }
                if !question.mainline.isEmpty {
                    HStack(spacing: 5) {
                        Rectangle().fill(Palette.muted).frame(width: 14, height: 1)
                        Text(wording("点线：跨树证据", "Dotted: cross-tree evidence"))
                    }.foregroundStyle(Palette.muted)
                }
                if layoutOverride == nil { legend(wording("已记录实验", "Recorded experiment"), color: Palette.success) }
                else { legend(wording("研究推进 / 对照 / 拓展", "Motivates / controls / extends"), color: Palette.accent) }
                legend(wording("支持", "Supports"), color: Palette.success)
                legend(wording("反驳", "Contradicts"), color: Palette.warning)
                Spacer()
                Text(canMoveNodes ? wording("画布内滚动平移，画布外滚动页面；拖动节点；⌘滚动缩放。", "Scroll inside to pan, outside to scroll the page; drag nodes; ⌘ scroll to zoom.")
                    : wording("画布内滚动平移，画布外滚动页面；⌘滚动缩放；单击空白关闭详情。", "Scroll inside to pan, outside to scroll the page; ⌘ scroll to zoom; click empty space to close details."))
                    .foregroundStyle(Palette.muted)
            }.font(.system(size: 10)).padding(.horizontal, 18).frame(height: 37)
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 0.7))
        .onChange(of: question) { old, new in
            cachedLayout = ScienceGraphLayout(question: new, language: language)
            for (id, point) in pendingDrops where new.graphPositions[id.uuidString] == point {
                dragOffsets[id] = nil
                pendingDrops[id] = nil
            }
            if old.id != new.id {
                selectedID = nil; hoveredID = nil; dragOffsets = [:]; pendingDrops = [:]; fit(layout)
            } else {
                pan = boundedPan(pan, map: layout, zoom: scale)
            }
            refreshFullScreen()
        }
        .onChange(of: language) { _, new in
            cachedLayout = ScienceGraphLayout(question: question, language: new)
            pan = boundedPan(pan, map: layout, zoom: scale)
            refreshFullScreen()
        }
        .onChange(of: layoutOverride?.nodes) { _, _ in refreshFullScreen() }
        .onChange(of: layoutOverride?.edges) { _, _ in refreshFullScreen() }
        .onDisappear { pointerInsideCanvas = false; fullScreenWindow.close() }
    }

    private var fullScreenTitle: String { wording("知识树 · ", "Knowledge tree · ") + question.title }
    private var fullScreenMap: ScienceMindMapView {
        ScienceMindMapView(question: question, language: language, canEdit: false, canMoveNodes: canMoveNodes,
            experimentName: experimentName, moveNode: moveNode, resetLayout: resetLayout, addClaim: {}, addAtom: {},
            editQuestion: {}, editClaim: { _ in }, editAtom: { _ in }, linkClaim: { _ in }, linkAtom: { _ in },
            fitsAvailableHeight: true, layoutOverride: layoutOverride, titleOverride: titleOverride, summaryOverride: summaryOverride,
            offersFullScreen: false)
    }
    private func refreshFullScreen() {
        guard offersFullScreen, fullScreenWindow.isPresented else { return }
        fullScreenWindow.update(title: fullScreenTitle, languageIsEnglish: language == .english, content: AnyView(fullScreenMap))
    }

    private func graphPlane(_ map: ScienceGraphLayout) -> some View {
        let nodesByID = Dictionary(uniqueKeysWithValues: map.nodes.map { ($0.id, $0) })
        let related = relatedIDs(map)
        let directedPairs = Set(map.edges.map { $0.fromID.uuidString + "|" + $0.toID.uuidString })
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for edge in map.edges {
                    guard let from = nodesByID[edge.fromID], let to = nodesByID[edge.toID] else { continue }
                    let sourceOffset = dragOffsets[from.id] ?? .zero
                    let targetOffset = dragOffsets[to.id] ?? .zero
                    let source = CGPoint(x: from.position.x + sourceOffset.width, y: from.position.y + sourceOffset.height)
                    let target = CGPoint(x: to.position.x + targetOffset.width, y: to.position.y + targetOffset.height)
                    let horizontal = (edge.kind == .progression && edge.caption.isEmpty) || abs(target.y - source.y) < 65
                    let direction: CGFloat = horizontal ? (target.x >= source.x ? 1 : -1) : (target.y >= source.y ? 1 : -1)
                    let feedback = layoutOverride != nil && directedPairs.contains(edge.toID.uuidString + "|" + edge.fromID.uuidString)
                    let offset: CGFloat = feedback ? (edge.fromID.uuidString < edge.toID.uuidString ? -30 : 30) : 0
                    let start = horizontal ? CGPoint(x: source.x + direction * 116, y: source.y + offset)
                        : CGPoint(x: source.x + offset, y: source.y + direction * 50)
                    let end = horizontal ? CGPoint(x: target.x - direction * 116, y: target.y + offset)
                        : CGPoint(x: target.x + offset, y: target.y - direction * 50)
                    let bend = horizontal ? min(70, abs(end.x - start.x) * 0.45) : min(80, abs(end.y - start.y) * 0.45)
                    let acrossMainline = edge.kind != .progression && from.mainlineNumber != nil && to.mainlineNumber != nil && abs(target.x - source.x) > 400
                    let arc: CGFloat = acrossMainline ? (edge.kind == .contradicts ? 140 : -140) : 0
                    let control1 = horizontal ? CGPoint(x: start.x + direction * bend, y: start.y + arc)
                        : CGPoint(x: start.x, y: start.y + direction * bend)
                    let control2 = horizontal ? CGPoint(x: end.x - direction * bend, y: end.y + arc)
                        : CGPoint(x: end.x, y: end.y - direction * bend)
                    let color: Color = switch edge.kind {
                    case .supports: Palette.success
                    case .contradicts: Palette.warning
                    case .addresses: Palette.muted.opacity(0.55)
                    case .progression: Palette.accent
                    }
                    var line = Path()
                    line.move(to: start)
                    line.addCurve(to: end, control1: control1, control2: control2)
                    let active = focusID == nil || (related.contains(edge.fromID) && related.contains(edge.toID))
                    context.stroke(line, with: .color(color.opacity(active ? 1 : 0.13)), style: StrokeStyle(lineWidth: active ? (edge.kind == .progression ? 3.2 : edge.kind == .addresses ? 1.3 : 2) : 1,
                        lineCap: .round, dash: edge.kind == .contradicts ? [7, 5] : edge.isCrossTree ? [2, 4] : []))
                    var arrow = Path()
                    arrow.move(to: end)
                    arrow.addLine(to: horizontal ? CGPoint(x: end.x - direction * 8, y: end.y - 5) : CGPoint(x: end.x - 5, y: end.y - direction * 8))
                    arrow.addLine(to: horizontal ? CGPoint(x: end.x - direction * 8, y: end.y + 5) : CGPoint(x: end.x + 5, y: end.y - direction * 8))
                    arrow.closeSubpath()
                    context.fill(arrow, with: .color(color.opacity(active ? 1 : 0.13)))
                    if edge.kind == .progression || !edge.caption.isEmpty {
                        let caption = context.resolve(Text(edge.caption.isEmpty ? wording("研究推进", "Next question") : edge.caption)
                            .font(.system(size: 10, weight: .medium)).foregroundColor(color.opacity(active ? 1 : 0.2)))
                        let size = caption.measure(in: CGSize(width: 180, height: 30))
                        let point = CGPoint(x: (start.x + end.x) / 2 + (feedback && !horizontal ? offset * 2 : 0),
                                            y: (start.y + end.y) / 2 - (edge.caption.isEmpty ? 66 : 17))
                        if !edge.caption.isEmpty {
                            context.fill(Path(roundedRect: CGRect(x: point.x - size.width / 2 - 4, y: point.y - size.height / 2 - 2,
                                width: size.width + 8, height: size.height + 4), cornerRadius: 3), with: .color(Palette.surface))
                        }
                        context.draw(caption, at: point)
                    }
                }
            }.allowsHitTesting(false)
            ForEach(map.nodes) { node in
                nodeView(node, related: related)
            }
        }
    }

    private func nodeView(_ node: ScienceGraphNode, related: Set<UUID>) -> some View {
        let button = Button { selectedID = node.id } label: { nodeCard(node, selected: selectedID == node.id) }
            .buttonStyle(.plain)
            .opacity(focusID == nil || related.contains(node.id) ? 1 : 0.48)
            .onHover { inside in hoveredID = inside ? node.id : (hoveredID == node.id ? nil : hoveredID) }
            .accessibilityLabel("\(node.subtitle): \(node.title)")
            .frame(width: 232, height: 100)
            .contentShape(Rectangle())
        return Group {
            if canMoveNodes {
                button.highPriorityGesture(nodeDragGesture(node))
                    .help(wording("拖动模块调整位置，点按查看详情", "Drag to move this node; click for details"))
            } else { button }
        }
        .position(x: node.position.x, y: node.position.y)
        .offset(dragOffsets[node.id] ?? .zero)
    }

    private func nodeDragGesture(_ node: ScienceGraphNode) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("scienceMapViewport"))
            .onChanged { value in
                pendingDrops[node.id] = nil
                dragOffsets[node.id] = CGSize(width: value.translation.width / scale,
                                              height: value.translation.height / scale)
            }
            .onEnded { value in
                let point = ScienceGraphPoint(
                    x: max(116, min(50_000, node.position.x + value.translation.width / scale)),
                    y: max(54, min(50_000, node.position.y + value.translation.height / scale))
                )
                if point == node.position || !moveNode(node.id, point) {
                    dragOffsets[node.id] = nil
                } else {
                    // The parent persists this position. Keep the visual drop offset until
                    // its updated graph arrives, so the card never jumps to its old location.
                    pendingDrops[node.id] = point
                }
            }
    }

    private func nodeCard(_ node: ScienceGraphNode, selected: Bool) -> some View {
        let tint: Color = switch node.kind {
        case .question: Palette.accent
        case .claim(let kind): kind == .conclusion ? Palette.ink : Palette.accent
        case .atomicExperiment(let status): status == .recorded ? Palette.success : Palette.muted
        }
        let symbol: String = switch node.kind {
        case .question: "questionmark.circle"
        case .claim(let kind): kind == .conclusion ? "checkmark.seal" : "text.bubble"
        case .atomicExperiment: "flask"
        }
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(node.subtitle).lineLimit(1)
                Spacer(minLength: 0)
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(tint)
            Text(node.title).font(.system(size: 12, weight: .semibold)).lineLimit(3)
                .multilineTextAlignment(.leading).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(node.mainlineNumber != nil ? Palette.selection : Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? tint : Palette.line, lineWidth: selected ? 1.5 : 0.8))
            .shadow(color: Palette.ink.opacity(selected ? 0.1 : 0.04), radius: selected ? 12 : 5, y: 2)
    }

    private func inspector(_ node: ScienceGraphNode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Eyebrow(text: "NODE DETAILS"); Spacer(); Button { selectedID = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("关闭详情") }
                Text(node.title).font(EditorialType.title(20)).fixedSize(horizontal: false, vertical: true)
                Text(node.subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted)
                nodeDetails(node)
                evidenceDetails(node)
                if canMoveNodes {
                    HStack(spacing: 12) {
                        moveButton("arrow.left", label: wording("左移", "Move Left"), node: node, dx: -40, dy: 0)
                        moveButton("arrow.up", label: wording("上移", "Move Up"), node: node, dx: 0, dy: -40)
                        moveButton("arrow.down", label: wording("下移", "Move Down"), node: node, dx: 0, dy: 40)
                        moveButton("arrow.right", label: wording("右移", "Move Right"), node: node, dx: 40, dy: 0)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(17)
        }.scrollIndicators(.hidden)
    }

    @ViewBuilder private func nodeDetails(_ node: ScienceGraphNode) -> some View {
                switch node.kind {
                case .question:
                    if !question.detail.isEmpty { Text(question.detail).font(.system(size: 12)).foregroundStyle(Palette.muted) }
                    if canEdit { Button("编辑问题", systemImage: "square.and.pencil", action: editQuestion).buttonStyle(QuietButtonStyle()) }
                case .claim:
                    if let claim = question.claims.first(where: { $0.id == node.id }) {
                        if let step = question.mainline.first(where: { $0.claimID == node.id }) {
                            Text(wording("本轮问题\n", "Research question\n") + step.question).font(.system(size: 12, weight: .medium))
                            Text(wording("为什么研究这一步\n", "Why this next check\n") + (step.motivation.isEmpty ? wording("承接理由待补充", "Rationale not recorded") : step.motivation))
                                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                            if step.origin == .inferred { Text(wording("承接理由为归纳，需核对", "Reconstructed rationale; verify")).font(.system(size: 10)).foregroundStyle(Palette.warning) }
                        }
                        if !claim.sourceNote.isEmpty { Text(wording("出处：\(claim.sourceNote)", "Source: \(claim.sourceNote)")).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                        if !claim.experimentIDs.isEmpty { Text(wording("相关实验：\(claim.experimentIDs.map(experimentName).joined(separator: "、"))", "Related experiments: \(claim.experimentIDs.map(experimentName).joined(separator: ", "))")).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                        if canEdit {
                            Button("连接到另一论断", systemImage: "arrow.triangle.branch", action: { linkClaim(claim.id) }).buttonStyle(QuietButtonStyle(prominent: true)).disabled(question.claims.count < 2)
                            Button("编辑论断", systemImage: "square.and.pencil", action: { editClaim(claim.id) }).buttonStyle(QuietButtonStyle())
                        }
                    }
                case .atomicExperiment:
                    if let atom = question.atomicExperiments.first(where: { $0.id == node.id }) {
                        if !atom.method.isEmpty { Text(wording("方法\n\(atom.method)", "Method\n\(atom.method)")).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                        if !atom.observedResult.isEmpty { Text(wording("观察结果\n\(atom.observedResult)", "Observed result\n\(atom.observedResult)")).font(.system(size: 11)).foregroundStyle(Palette.ink) }
                        if let id = atom.experimentID { Text(wording("所属实验：\(experimentName(id))", "Related experiment: \(experimentName(id))")).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                        if !atom.sourceNote.isEmpty { Text(wording("出处：\(atom.sourceNote)", "Source: \(atom.sourceNote)")).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                        if atom.status == .recorded {
                            if canEdit { Button("连接到论断", systemImage: "arrow.triangle.branch", action: { linkAtom(atom.id) }).buttonStyle(QuietButtonStyle(prominent: true)).disabled(question.claims.isEmpty) }
                        } else {
                            Text(wording("先记录观察结果，才能作为支持或反驳证据。", "Record an observation before using this test as supporting or contradicting evidence.")).font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }
                        if canEdit { Button("编辑原子实验", systemImage: "square.and.pencil", action: { editAtom(atom.id) }).buttonStyle(QuietButtonStyle()) }
                    }
                }
    }

    private func claimTitle(_ id: UUID) -> String { question.claims.first { $0.id == id }?.text ?? "" }

    private func evidenceDetails(_ node: ScienceGraphNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
                if let map = layoutOverride {
                    ForEach(Array(map.edges.filter { $0.fromID == node.id || $0.toID == node.id }.enumerated()), id: \.offset) { _, edge in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(claimTitle(edge.fromID) + " → " + claimTitle(edge.toID)).font(.system(size: 11, weight: .medium))
                            Text(edge.label).font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }
                    }
                }
                ForEach(question.evidenceLinks.filter { $0.atomicExperimentID == node.id || $0.claimID == node.id }) { edge in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(edge.kind.title(language) + " → " + claimTitle(edge.claimID))
                            .font(.system(size: 11, weight: .medium))
                        Text(edge.explanation.isEmpty ? wording("论证依据待补充", "Warrant not recorded") : edge.explanation).font(.system(size: 11))
                        if !edge.limitations.isEmpty { Text(wording("解释边界：", "Inferential boundary: ") + edge.limitations).font(.system(size: 10)).foregroundStyle(Palette.muted) }
                    }
                }
                ForEach(question.relations.filter { $0.fromClaimID == node.id || $0.toClaimID == node.id }) { edge in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(claimTitle(edge.fromClaimID) + " → " + claimTitle(edge.toClaimID))
                            .font(.system(size: 11, weight: .medium))
                        Text(edge.kind.title(language) + " · " + (edge.explanation.isEmpty ? wording("论证依据待补充", "Warrant not recorded") : edge.explanation)).font(.system(size: 11))
                        if !edge.limitations.isEmpty { Text(wording("解释边界：", "Inferential boundary: ") + edge.limitations).font(.system(size: 10)).foregroundStyle(Palette.muted) }
                    }
                }
        }
    }

    private func moveButton(_ symbol: String, label: String, node: ScienceGraphNode, dx: Double, dy: Double) -> some View {
        Button {
            _ = moveNode(node.id, ScienceGraphPoint(
                x: max(116, min(50_000, node.position.x + dx)),
                y: max(54, min(50_000, node.position.y + dy))
            ))
        } label: {
            Image(systemName: symbol).frame(width: 26, height: 26)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
        .help(label)
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 5, height: 5); Text(title) }.foregroundStyle(Palette.muted)
    }
}
