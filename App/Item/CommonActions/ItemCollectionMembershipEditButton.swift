//
//  ItemCollectionMembershipEditButton.swift
//  Library
//
//  Created by Rasmus Krämer on 22.07.25.
//

import SwiftUI
struct ItemCollectionMembershipEditButton: View {
    @Environment(OfflineMode.self) private var offlineMode
    @Environment(Satellite.self) private var satellite

    let itemID: ItemIdentifier

    var body: some View {
        Button("item.collection.editMembership.open", systemImage: ItemIdentifier.ItemType.playlist.icon) {
            satellite.present(.editCollectionMembership(itemID))
        }
        .disabled(offlineMode.isEnabled)
    }
}
