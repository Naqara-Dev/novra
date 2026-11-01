import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    case spaceLens, memory, docker, homebrew, nix, snapshots, simulators, externalDrive, trash,
         dns, spotlight, launchServices, quickLook, preferences, databases, permissions, verifyDisk, maintenance,
         dsStore, quarantine, shredder

    enum Group: String, CaseIterable { case cleanup = "Clean up", fix = "Fix & maintain", privacy = "Privacy" }

    var group: Group {
        switch self {
        case .docker, .homebrew, .nix, .snapshots, .simulators, .externalDrive, .trash, .spaceLens, .memory: .cleanup
        case .dns, .spotlight, .launchServices, .quickLook, .preferences, .databases, .permissions, .verifyDisk, .maintenance: .fix
        case .dsStore, .quarantine, .shredder: .privacy
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spaceLens: String(localized: "Space Lens")
        case .memory: String(localized: "Memory")
        case .docker: String(localized: "Docker Cleanup")
        case .homebrew: String(localized: "Homebrew Cleanup")
        case .nix: String(localized: "Nix Garbage Collection")
        case .externalDrive: String(localized: "Clean External Drive")
        case .preferences: String(localized: "Repair Preferences")
        case .databases: String(localized: "Compact Mail, Safari & Messages")
        case .permissions: String(localized: "Repair Home Permissions")
        case .verifyDisk: String(localized: "Verify Disk")
        case .maintenance: String(localized: "Run Maintenance Scripts")
        case .dsStore: String(localized: "No .DS_Store on Drives")
        case .quarantine: String(localized: "Clear Download History")
        case .snapshots: String(localized: "Time Machine Snapshots")
        case .simulators: String(localized: "Old Simulators")
        case .trash: String(localized: "Empty Trash")
        case .dns: String(localized: "Flush DNS & ARP")
        case .spotlight: String(localized: "Reindex Spotlight")
        case .launchServices: String(localized: "Fix “Open With” Menu")
        case .quickLook: String(localized: "Reset Quick Look")
        case .shredder: String(localized: "Shredder")
        }
    }

    var subtitle: String {
        switch self {
        case .spaceLens: String(localized: "See your disk as a map. Dive into any folder and pick what goes.")
        case .memory: String(localized: "Live memory use, and the apps holding the most.")
        case .docker: String(localized: "Dangling images and build cache.")
        case .homebrew: String(localized: "Old package versions, downloads and dependencies nothing needs anymore.")
        case .nix: String(localized: "Store paths no profile or project uses anymore.")
        case .externalDrive: String(localized: "Remove ._ files, .DS_Store and temp folders macOS leaves on USB drives.")
        case .preferences: String(localized: "Find settings files that are damaged and can make apps misbehave.")
        case .databases: String(localized: "Shrink the databases behind Mail, Safari history and Messages.")
        case .permissions: String(localized: "Fixes “you don't have permission” errors inside your own folders.")
        case .verifyDisk: String(localized: "Checks your startup disk for errors. Read-only.")
        case .maintenance: String(localized: "macOS's own daily, weekly and monthly housekeeping, run now.")
        case .dsStore: String(localized: "Stop the Mac leaving hidden .DS_Store files on USB and network drives.")
        case .quarantine: String(localized: "macOS keeps a log of every file you've ever downloaded. Wipe it.")
        case .snapshots: String(localized: "Local backups macOS keeps on your disk as purgeable space.")
        case .simulators: String(localized: "Xcode simulators for runtimes you no longer have.")
        case .trash: String(localized: "Get back the space your Trash is holding.")
        case .dns: String(localized: "Fixes sites that won't load after a network change.")
        case .spotlight: String(localized: "Rebuilds search when results are missing or wrong.")
        case .launchServices: String(localized: "Removes duplicate apps from the Open With menu.")
        case .quickLook: String(localized: "Fixes blank or stale file previews.")
        case .shredder: String(localized: "Delete files for good, skipping the Trash.")
        }
    }

    var icon: String {
        switch self {
        case .spaceLens: "chart.pie.fill"
        case .memory: "memorychip.fill"
        case .docker: "shippingbox.fill"
        case .homebrew: "mug.fill"
        case .nix: "snowflake"
        case .externalDrive: "externaldrive.fill.badge.minus"
        case .preferences: "wrench.adjustable.fill"
        case .databases: "cylinder.split.1x2.fill"
        case .permissions: "lock.open.fill"
        case .verifyDisk: "stethoscope"
        case .maintenance: "calendar.badge.clock"
        case .dsStore: "externaldrive.badge.xmark"
        case .quarantine: "hand.raised.fill"
        case .snapshots: "clock.arrow.circlepath"
        case .simulators: "iphone.gen3"
        case .trash: "trash.fill"
        case .dns: "network"
        case .spotlight: "magnifyingglass"
        case .launchServices: "contextualmenu.and.cursorarrow"
        case .quickLook: "eye.fill"
        case .shredder: "doc.badge.ellipsis"
        }
    }

    var colors: [Color] {
        switch self {
        case .spaceLens: [Color(hex: 0x3D7BF7), Color(hex: 0x7B61FF)]
        case .memory: [Color(hex: 0x32D583), Color(hex: 0x0EA5A4)]
        case .docker: [Color(hex: 0x2496ED), Color(hex: 0x1D63ED)]
        case .homebrew: [Color(hex: 0xFBB040), Color(hex: 0xC9781E)]
        case .nix: [Color(hex: 0x7EB6FF), Color(hex: 0x5277C3)]
        case .externalDrive: [Color(hex: 0xFF9F0A), Color(hex: 0xD9730D)]
        case .preferences: [Color(hex: 0x32D583), Color(hex: 0x1E9E5E)]
        case .databases: [Color(hex: 0x37B6FF), Color(hex: 0x1D63ED)]
        case .permissions: [Color(hex: 0xFFB547), Color(hex: 0xE08A00)]
        case .verifyDisk: [Color(hex: 0xFF6B6B), Color(hex: 0xC43A3A)]
        case .maintenance: [Color(hex: 0x9B7BFF), Color(hex: 0x6A4BD6)]
        case .dsStore: [Color(hex: 0x9AA7D6), Color(hex: 0x5D6AA0)]
        case .quarantine: [Color(hex: 0x4FC3A1), Color(hex: 0x23806A)]
        case .snapshots: [Color(hex: 0x8E9BC7), Color(hex: 0x5B6BA8)]
        case .simulators: [Color(hex: 0x7B61FF), Color(hex: 0x4C3BD1)]
        case .trash: [Color(hex: 0xFF6B6B), Color(hex: 0xE5484D)]
        case .dns: [Color(hex: 0x37B6FF), Color(hex: 0x2A7FD4)]
        case .spotlight: [Color(hex: 0xA9B8FF), Color(hex: 0x6E7FF3)]
        case .launchServices: [Color(hex: 0xFFB547), Color(hex: 0xFF8A00)]
        case .quickLook: [Color(hex: 0x4FC3A1), Color(hex: 0x2E9E80)]
        case .shredder: [Color(hex: 0xFF5A8A), Color(hex: 0xC43A6B)]
        }
    }

    /// Opens its own page instead of running in place.
    var hasPage: Bool { [.spaceLens, .memory, .shredder].contains(self) }

    /// Shown before running; nil runs right away.
    var confirmation: String? {
        switch self {
        case .docker: String(localized: "Removes dangling images and build cache. Containers, running or stopped, and volumes are never touched.")
        case .snapshots: String(localized: "Deletes local Time Machine snapshots on this Mac. Backups on your backup disk are not touched. macOS will ask for your password.")
        case .simulators: String(localized: "Deletes simulators whose iOS runtime is no longer installed. Their apps and data go with them.")
        case .trash: String(localized: "Everything in the Trash is deleted for good.")
        case .homebrew: String(localized: "Runs brew cleanup --prune=30 and brew autoremove. Packages you installed keep working; old versions, downloads and orphaned dependencies go.")
        case .nix: String(localized: "Runs nix-store --gc. Anything still referenced by a profile stays.")
        case .externalDrive: String(localized: "You'll pick a drive. Novra removes ._ files, .DS_Store and .TemporaryItems on it. The drive's Trash and Spotlight index are left alone.")
        case .databases: String(localized: "Quit Mail, Safari and Messages first. Nothing is deleted; the databases are just rewritten compactly.")
        case .permissions: String(localized: "Runs diskutil resetUserPermissions on your home folder. Takes a few minutes. macOS will ask for your password.")
        case .maintenance: String(localized: "Runs periodic daily weekly monthly. macOS will ask for your password.")
        case .dns: String(localized: "Clears the DNS and ARP caches. macOS will ask for your password.")
        case .dsStore: String(localized: "Finder stops writing .DS_Store files to USB and network drives. Folder view settings on those drives won't be remembered. Takes effect after you log out.")
        case .quarantine: String(localized: "Clears the record macOS keeps of where every downloaded file came from. Gatekeeper protection is not affected.")
        case .spotlight: String(localized: "Spotlight rebuilds its index in the background. Search may be incomplete for a while. macOS will ask for your password.")
        default: nil
        }
    }
}

struct ToolIcon: View {
    var tool: Tool
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: tool.icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(LinearGradient(colors: tool.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: tool.colors[0].opacity(0.45), radius: size * 0.25, y: size * 0.1)
    }
}
