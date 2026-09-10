//
//  CicadaApp.swift
//  Cicada
//
//  输入法主 App:进程内承载 IMKServer 与设置界面;引擎经 RimeKit 驱动,
//  蓝绿双 XPC 服务嵌入本 Bundle(Contents/XPCServices,§4.1)。
//
//  当前为占位壳:IMKServer 装配与设置界面待 RimeIMKSupport 落地后接入。
//  LSUIElement 生效(App 无 Dock 图标),激活输入法走系统输入源设置。
//

import SwiftUI

@main
struct CicadaApp: App {
    var body: some Scene {
        Settings {
            Text("Cicada 输入法")
        }
    }
}
