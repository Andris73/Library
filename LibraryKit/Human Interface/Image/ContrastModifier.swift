//
//  ContrastModifier.swift
//  LibraryKit
//

import SwiftUI

struct ContrastModifier: ViewModifier {
    @Environment(\.library) private var library

    let itemID: ItemIdentifier?
    let cornerRadius: CGFloat
    let configuration: ItemImage.ContrastConfiguration?

    private var libraryType: LibraryMediaType? {
        if let itemID {
            switch itemID.type {
            case .audiobook, .author, .narrator, .series, .collection, .playlist: .audiobooks
            }
        } else if let library {
            library.id.type
        } else {
            nil
        }
    }

    func body(content: Content) -> some View {
        if let configuration {
            switch libraryType {
            case .audiobooks:
                content
                    .secondaryShadow(radius: configuration.shadowRadius, opacity: configuration.shadowOpacity)
            case .audiobooks: // was podcasts
                content
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(.gray.opacity(configuration.borderOpacity), lineWidth: configuration.borderThickness)
                    }
            default:
                content
            }
        } else {
            content
        }
    }
}
