//
//  ImageInspection.swift
//  WICompressTests
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain
@testable import WIImageIO

func imageFormat(of data: Data) throws -> ImageFormat {
    try ImageReader.inspect(data).format
}
