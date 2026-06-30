//
//  Progress+ConvertOffline.swift
//  LibraryKit
//
//  Created by Rasmus Krämer on 23.12.24.
//

extension ProgressEntity {
    init(persistedEntity: PersistedProgress) {
        self.init(id: persistedEntity.id,
                  connectionID: persistedEntity.connectionID,
                  primaryID: persistedEntity.primaryID,
                  groupingID: persistedEntity.groupingID,
                  progress: persistedEntity.progress,
                  startedAt: persistedEntity.startedAt,
                  lastUpdate: persistedEntity.lastUpdate,
                  finishedAt: persistedEntity.finishedAt)
    }
}
