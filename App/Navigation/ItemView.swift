//
//  ItemView.swift
//  Library
//
//  Created by Rasmus Krämer on 22.07.25.
//

import SwiftUI
struct ItemView: View {
    let item: Item

    var zoomID: UUID?

    var body: some View {
        if let audiobook = item as? Audiobook {
            AudiobookView(audiobook)
        } else if let series = item as? Series {
            SeriesView(series)
        } else if let person = item as? Person {
            PersonView(person)
        } else if let collection = item as? ItemCollection {
            CollectionView(collection)
        } else {
            ErrorView()
        }
    }
}
