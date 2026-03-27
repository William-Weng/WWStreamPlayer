//
//  Constant.swift
//  WWStreamPlayer
//
//  Created by William.Weng on 2026/3/27.
//

import Foundation

// MARK: - enum
public extension WWStreamPlayer {

    /// 取得串流的形式
    enum PlayerType: CaseIterable {
        case image          // 圖片
        case displayLayer   // Layer
        case pixelBuffer    // Buffer
    }
}
