//
//  WIExecutionPlan.swift
//  WICompressExecution
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain
import WIImageIO

struct WIExecutionPlan: Sendable, Equatable {
    enum Operation: Sendable, Equatable {
        case returnOriginal
        case copyFromSource
        case render(WIResolvedRender)
    }

    let operation: Operation
    let destinationFormat: WIImageFormat
    let destinationTypeIdentifier: String
    let metadata: WIImageMetadata
    var quality: Double?
    let jpegBackground: WIJPEGBackground?
    let outputColorSpace: WIResolvedOutputColorSpace
}

struct WIResolvedRender: Sendable, Equatable {
    let sourceRect: Rect
    let canvasSize: WIPixelSize
    let destinationRect: Rect
    let canvasBackground: WIColor?
}
