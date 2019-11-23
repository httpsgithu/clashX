//
//  TunManager.swift
//  ClashX
//
//  Created by yichengchen on 2019/11/23.
//  Copyright © 2019 west2online. All rights reserved.
//

import Cocoa

class TunManager {
    static func addTunMenuItem(_ menu: inout NSMenu) {
        menu.addItem(NSMenuItem.separator())

        let item = NSMenuItem(title: "Clear Dns Cache", action: #selector(SystemProxyManager.clearDnsCache), keyEquivalent: "")
        item.target = SystemProxyManager.shared
        menu.addItem(item)

        let item2 = NSMenuItem(title: "Update Forwarding Options", action: #selector(SystemProxyManager.updateForwardingOptions), keyEquivalent: "")
        item2.target = SystemProxyManager.shared
        menu.addItem(item2)

        let item3 = NSMenuItem(title: "Set Clash Dns", action: #selector(SystemProxyManager.setLocalDns), keyEquivalent: "")
        item3.target = SystemProxyManager.shared
        menu.addItem(item3)

        let item4 = NSMenuItem(title: "Restore Dns", action: #selector(SystemProxyManager.restoreDnsSetting), keyEquivalent: "")
        item4.target = SystemProxyManager.shared
        menu.addItem(item4)
    }
}
