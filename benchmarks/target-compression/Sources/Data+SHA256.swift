//
//  Data+SHA256.swift
//  TargetCompressionBenchmark
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CryptoKit
import Foundation

extension Data {
    var sha256: String {
        SHA256.hash(data: self).map {
            String(format: "%02x", $0)
        }
        .joined()
    }
}
