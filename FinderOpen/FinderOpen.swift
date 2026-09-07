//
//  FinderSync.swift
//  FinderOpen
//
//  Created by Alin Lupascu on 4/11/24.
//

import Cocoa
import FinderSync

class FinderOpen: FIFinderSync {

    /// Finder Sync menus are intentionally limited to the standard application
    /// locations. The extension only receives selected URLs from Finder and
    /// hands them to the main app; it does not need a filesystem exception.
    private static let observedApplicationDirectories: Set<URL> = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true),
    ]

    override init() {
        super.init()
        NSLog("FinderSync() launched from %@", Bundle.main.bundlePath as NSString)
        FIFinderSyncController.default().directoryURLs = Self.observedApplicationDirectories
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")

        // Ensure we are dealing with the contextual menu for items
        if menuKind == .contextualMenuForItems {
            // Get the selected items
            if let selectedItemURLs = FIFinderSyncController.default().selectedItemURLs(),
               selectedItemURLs.count == 1, selectedItemURLs.first?.pathExtension == "app" {
                // Add menu item if the selected item is a .app file
                let menuItem = NSMenuItem(title: "Uninstall with Silocleaner", action: #selector(openInMyApp), keyEquivalent: "")
                // Add icon if enabled in main app
                if UserDefaults.showAppIconInMenu {
                    if let appIcon = NSApp.applicationIconImage {
                        appIcon.size = NSSize(width: 16, height: 16)
                        menuItem.image = appIcon
                    } else if let fallbackIcon = NSImage(named: "Glass") {
                        fallbackIcon.size = NSSize(width: 16, height: 16)
                        menuItem.image = fallbackIcon
                    }
                }
                menu.addItem(menuItem)

            }
        }

        // Return the menu (which may be empty if the conditions are not met)
        return menu

    }

    @objc func openInMyApp(_ sender: AnyObject?) {
        // Get the selected items (files/folders) in Finder
        guard let selectedItems = FIFinderSyncController.default().selectedItemURLs(), !selectedItems.isEmpty else {
            return
        }

        // Consider only the first selected item
        let firstSelectedItem = selectedItems[0]
        var components = URLComponents()
        components.scheme = "silocleaner"
        components.host = "com.lindemannm.Silocleaner"
        components.queryItems = [URLQueryItem(name: "path", value: firstSelectedItem.path)]

        guard let deepLink = components.url else {
            return
        }
        NSWorkspace.shared.open(deepLink)

    }

}
