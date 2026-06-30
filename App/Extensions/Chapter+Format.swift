//
//  Chapter+Format.swift
//  Library
//
//  Created by Rasmus Krämer on 29.04.25.
//

import Foundation
extension Chapter {
    var timeOffsetFormatted: String {
        "\(startOffset.formatted(.duration(unitsStyle: .positional, allowedUnits: [.hour, .minute, .second], maximumUnitCount: 3))) - \(endOffset.formatted(.duration(unitsStyle: .positional, allowedUnits: [.hour, .minute, .second], maximumUnitCount: 3))) • \((endOffset - startOffset).formatted(.duration(unitsStyle: .positional, allowedUnits: [.hour, .minute, .second], maximumUnitCount: 3)))"
    }
}
