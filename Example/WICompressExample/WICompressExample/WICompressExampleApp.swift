//
//  WICompressExampleApp.swift
//  WICompressExample
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import SwiftUI

@main
struct WICompressExampleApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                WICompressExampleView()
                    .tabItem {
                        Label("PhotosPicker", systemImage: "photo.on.rectangle")
                    }
                
                UIKitPickerView()
                    .tabItem {
                        Label("PHPicker", systemImage: "photo.stack")
                    }
            }
        }
    }
}
