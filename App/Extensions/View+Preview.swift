//
//  View+Preview.swift
//  Library
//
//  Created by Rasmus Krämer on 17.10.24.
//

import Foundation
import SwiftUI
extension View {
    #if DEBUG
    @ViewBuilder
    func previewEnvironment() -> some View {
        @Namespace var namespace

        self
            .environment(ConnectionStore.shared)
            .environment(ItemNavigationController())
            .environment(TabRouterViewModel().previewEnvironment())
            .environment(\.namespace, namespace)
    }
    #endif
}
