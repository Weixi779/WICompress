//
//  WICompressExampleApp.swift
//  WICompressExample
//
//  Created by 孙世伟 on 2025/7/28.
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
