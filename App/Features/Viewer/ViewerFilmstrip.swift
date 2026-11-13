import MNGKit
import SwiftUI

/// Horizontally scrolling viewer filmstrip. The active frame is centered on
/// open and after navigation, and carries the PWA's white border, scale and
/// opacity treatment.
struct ViewerFilmstrip: View {
    let client: MNGAPIClient
    let items: [Item]
    let index: Int
    let onSelect: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { entry in
                        Button {
                            onSelect(entry.offset)
                        } label: {
                            thumbnail(entry.element, active: entry.offset == index)
                        }
                        .buttonStyle(.plain)
                        .id(entry.element.id)
                        .accessibilityLabel(
                            entry.element.name.isEmpty
                                ? Strings.itemCount(entry.offset + 1)
                                : entry.element.name
                        )
                        .accessibilityAddTraits(
                            entry.offset == index ? [.isSelected] : []
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 3)
            }
            .scrollIndicators(.hidden)
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 18)

                    Rectangle()
                        .fill(Color.black)

                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 18)
                }
            }
            .onAppear {
                guard items.indices.contains(index) else { return }
                let id = items[index].id
                DispatchQueue.main.async {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onChange(of: index) { oldValue, newValue in
                center(
                    proxy,
                    animated: !reduceMotion && abs(newValue - oldValue) <= 8
                )
            }
            .onChange(of: items.count) { _, _ in
                center(proxy, animated: false)
            }
        }
        .frame(height: 52)
        .accessibilityLabel(Strings.viewerStrip)
    }

    private func thumbnail(_ item: Item, active: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ThumbnailView(
                client: client,
                path: item.thumbnailPath(size: 160),
                fallbacks: item.thumbnailFallbackPaths,
                placeholder: Color.white.opacity(0.12)
            )
            .frame(width: 46, height: 46)

            if item.isVideo {
                Image(systemName: "play.fill")
                    .font(Font.mng(7, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .background(.black.opacity(0.62), in: Circle())
                    .padding(2)
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(active ? Color.white : Color.clear, lineWidth: 2)
        }
        .opacity(active ? 1 : 0.58)
        .scaleEffect(active ? 1.07 : 1)
        .shadow(
            color: active ? .black.opacity(0.5) : .clear,
            radius: 5,
            x: 0,
            y: 2
        )
        .contentShape(Rectangle())
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: active
        )
    }

    private func center(_ proxy: ScrollViewProxy, animated: Bool) {
        guard items.indices.contains(index) else { return }
        let id = items[index].id
        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}
