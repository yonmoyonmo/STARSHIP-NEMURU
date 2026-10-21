//
//  Item.swift
//  STARSHIP NEMURU
//
//  Created by yowenomo on 10/21/26.
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
