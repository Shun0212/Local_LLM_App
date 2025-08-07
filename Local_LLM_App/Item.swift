//
//  Item.swift
//  Local_LLM_App
//
//  Created by Shuu on 2025/08/08.
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
