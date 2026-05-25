//
//  Item.swift
//  ClipPixTran
//
//  Created by kriss k on 2026/5/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date

    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
