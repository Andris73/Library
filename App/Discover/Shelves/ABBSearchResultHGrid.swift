//
//  ABBSearchResultHGrid.swift
//  Library
//
//  Horizontal grid of AudiobookBay search results. Used by the Discover
//  tab's trending shelves. Mirrors the layout conventions of
//  `AudiobookHGrid` (fixed cell width, 2:3 cover, 2-line title) but
//  doesn't carry per-item progress state — `ABBSearchResult` is a
//  pre-resolved model with no listening-progress attachment.
//

import SwiftUI
import ABBKit

struct ABBSearchResultHGrid: View {
    private let gap: CGFloat = 12
    private let padding: CGFloat = 20
    private let cellWidth: CGFloat = 110

    let results: [ABBSearchResult]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: gap) {
                ForEach(results) { result in
                    NavigationLink(value: NavigationDestination.abbDetail(result)) {
                        ABBSearchResultCell(result: result, width: cellWidth)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, padding)
        }
        .scrollClipDisabled()
    }
}

struct ABBSearchResultCell: View {
    let result: ABBSearchResult
    let width: CGFloat

    private var coverHeight: CGFloat {
        width * 1.5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            cover
                .frame(width: width, height: coverHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(result.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
                .frame(width: width, alignment: .leading)
        }
        .frame(width: width)
    }

    @ViewBuilder
    private var cover: some View {
        ABBCoverImage(url: result.coverURL) {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.secondary.opacity(0.2))
            .overlay {
                Image(systemName: "book")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }
}
