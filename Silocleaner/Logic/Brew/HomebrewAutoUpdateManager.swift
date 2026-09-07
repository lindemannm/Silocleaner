//
//  HomebrewAutoUpdateManager.swift
//  Silocleaner
//
//  Created by Alin Lupascu on 10/25/25.
//

import Foundation
import AppKit
import AlinFoundation
import SwiftUI

// MARK: - Plist State

enum PlistState {
    case none      // No plist file exists
    case active    // Regular .plist exists
}

// MARK: - Schedule Model

enum ScheduleFrequency: String, Codable, Hashable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
}

struct ScheduleOccurrence: Identifiable, Codable, Hashable {
    let id: UUID
    var frequency: ScheduleFrequency
    var weekday: Int?      // 0=Sunday, 1=Monday, ... 6=Saturday (used for weekly)
    var dayOfMonth: Int?   // 1-28 (used for monthly)
    var hour: Int          // 0-23
    var minute: Int        // 0-59
    var isEnabled: Bool

    init(frequency: ScheduleFrequency = .weekly, weekday: Int? = nil, dayOfMonth: Int? = nil, hour: Int? = nil, minute: Int? = nil, isEnabled: Bool = true) {
        self.id = UUID()
        self.frequency = frequency

        // Use current date/time as defaults
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute, .day], from: now)

        // Set defaults based on frequency
        switch frequency {
        case .daily:
            self.weekday = nil
            self.dayOfMonth = nil
        case .weekly:
            // Convert Calendar.weekday (1=Sunday...7=Saturday) to our format (0=Sunday...6=Saturday)
            let currentWeekday = (components.weekday ?? 1) - 1
            self.weekday = weekday ?? currentWeekday
            self.dayOfMonth = nil
        case .monthly:
            self.weekday = nil
            self.dayOfMonth = dayOfMonth ?? min(components.day ?? 1, 28)  // Cap at 28 for safety
        }

        self.hour = hour ?? (components.hour ?? 9)
        self.minute = minute ?? (components.minute ?? 0)
        self.isEnabled = isEnabled
    }
}

// MARK: - AutoUpdate Manager

class HomebrewAutoUpdateManager: ObservableObject {
    static let shared = HomebrewAutoUpdateManager()

    @Published var schedules: [ScheduleOccurrence] = []
    @Published var isAgentLoaded: Bool = false
    @Published var logFileExists: Bool = false

    // Master toggle stored in UserDefaults (independent of schedule existence)
    @AppStorage("settings.brew.autoUpdateEnabled") var isEnabled: Bool = false

    // Store schedules when disabled (for restoration when re-enabled)
    @AppStorage("settings.brew.autoUpdatePreservedSchedules") private var preservedSchedulesData: Data = Data()

    // Computed property to access preserved schedules
    private var preservedSchedules: [ScheduleOccurrence] {
        get {
            guard let decoded = try? JSONDecoder().decode([ScheduleOccurrence].self, from: preservedSchedulesData) else {
                return []
            }
            return decoded
        }
        set {
            preservedSchedulesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    // Global actions that apply to ALL schedules
    @Published var runUpdate: Bool = true
    @Published var runUpgrade: Bool = true
    @Published var runCleanup: Bool = false

    // Store original state for comparison (to detect edit mode)
    @Published var originalSchedules: [ScheduleOccurrence] = []
    var originalRunUpdate: Bool = true
    var originalRunUpgrade: Bool = false
    var originalRunCleanup: Bool = false

    private let plistPath = "\(NSHomeDirectory())/Library/LaunchAgents/com.lindemannm.Silocleaner.homebrew-autoupdate.plist"
    private let label = "com.lindemannm.Silocleaner.homebrew-autoupdate"
    let logPath = "/tmp/homebrew-autoupdate.log"

    private init() {
        loadSchedule()
        checkAgentStatus()
        checkLogFiles()

        // Restore preserved schedules if disabled and no schedules loaded
        if !isEnabled && schedules.isEmpty && !preservedSchedules.isEmpty {
            schedules = preservedSchedules
            originalSchedules = preservedSchedules
        }

        // Auto-register agent if enabled with schedules but not running
        if isEnabled && !schedules.isEmpty && !isAgentLoaded {
            Task {
                do {
                    try applySchedule()
                } catch {
                    printOS("Failed to auto-register LaunchAgent on launch: \(error)")
                }
            }
        }
    }

    // MARK: - Public Methods

    /// Check which plist file exists (if any)
    var plistState: PlistState {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: plistPath) {
            return .active
        } else {
            return .none
        }
    }

    /// Toggle the entire schedule on/off
    func toggleEnabled(_ enabled: Bool) throws {
        let fileManager = FileManager.default

        if enabled {
            // Enable: Restore preserved schedules if available
            isEnabled = true

            // Always restore from preserved schedules when re-enabling (not just when empty)
            // This ensures deleted schedules don't reappear after toggle cycle
            if !preservedSchedules.isEmpty {
                schedules = preservedSchedules
                originalSchedules = preservedSchedules
            }

            // Apply schedules immediately if we have at least one enabled schedule
            let enabledCount = schedules.filter { $0.isEnabled }.count
            if enabledCount > 0 {
                try applySchedule()
            }
        } else {
            // Disable: Preserve schedules but clean up plist
            isEnabled = false

            // Always save current schedules to AppStorage before cleanup (even if empty)
            // This ensures deleted schedules are cleared from AppStorage
            preservedSchedules = schedules

            // Unregister agent if running
            try? unregisterAgent()

            // Delete plist entirely (don't rename to .disabled)
            if fileManager.fileExists(atPath: plistPath) {
                try fileManager.removeItem(atPath: plistPath)
            }

            // Keep schedules in memory (they'll show dimmed in UI)
        }

        checkAgentStatus()
    }

    /// Check if a schedule is in "edit mode" (new or modified)
    /// Note: isEnabled is excluded - it auto-saves immediately and doesn't trigger edit mode
    func isInEditMode(_ schedule: ScheduleOccurrence) -> Bool {
        // New schedule not in originals = edit mode
        if !originalSchedules.contains(where: { $0.id == schedule.id }) {
            return true
        }

        // Check if any property changed from original (excluding isEnabled)
        guard let original = originalSchedules.first(where: { $0.id == schedule.id }) else {
            return true
        }

        return original.frequency != schedule.frequency ||
               original.weekday != schedule.weekday ||
               original.dayOfMonth != schedule.dayOfMonth ||
               original.hour != schedule.hour ||
               original.minute != schedule.minute
    }

    /// Save a single schedule to plist
    func saveSchedule(_ schedule: ScheduleOccurrence) throws {
        guard isEnabled else { return }

        // Update original state
        if let index = originalSchedules.firstIndex(where: { $0.id == schedule.id }) {
            originalSchedules[index] = schedule
        } else {
            originalSchedules.append(schedule)
        }

        // Also update action originals
        originalRunUpdate = runUpdate
        originalRunUpgrade = runUpgrade
        originalRunCleanup = runCleanup

        // Apply to plist and register LaunchAgent
        try applySchedule()
    }

    /// Revert schedule to original state (exit edit mode without saving)
    func revertSchedule(_ schedule: ScheduleOccurrence) {
        // Find original schedule
        guard let original = originalSchedules.first(where: { $0.id == schedule.id }) else {
            return
        }

        // Find index in current schedules
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else {
            return
        }

        // Revert to original values (excluding isEnabled which is instant-save)
        schedules[index].frequency = original.frequency
        schedules[index].weekday = original.weekday
        schedules[index].dayOfMonth = original.dayOfMonth
        schedules[index].hour = original.hour
        schedules[index].minute = original.minute
    }

    /// Delete schedule and save to plist
    func deleteSchedule(_ schedule: ScheduleOccurrence) throws {
        // Remove from current schedules
        schedules.removeAll { $0.id == schedule.id }

        // Remove from originals
        originalSchedules.removeAll { $0.id == schedule.id }

        // Always update preserved schedules in AppStorage (not just when disabled)
        // This ensures deletions persist across toggle cycles
        var preserved = preservedSchedules
        preserved.removeAll { $0.id == schedule.id }
        preservedSchedules = preserved

        // Apply to plist (saves deletion)
        try applySchedule()
    }

    /// Apply current schedules by generating plist and registering LaunchAgent
    func applySchedule() throws {
        // Don't apply if master toggle is disabled
        guard isEnabled else {
            return
        }

        // Check if we have any enabled schedules
        let enabledSchedules = schedules.filter { $0.isEnabled }

        guard !enabledSchedules.isEmpty else {
            // No enabled schedules - clean up completely
            try unregisterAgent()

            // Delete plist file (no schedules = no file needed)
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: plistPath) {
                try fileManager.removeItem(atPath: plistPath)
            }

            checkAgentStatus()
            return
        }

        // Generate plist content
        let plistContent = generatePlist()

        // Validate plist format
        guard let data = plistContent.data(using: .utf8) else {
            throw HomebrewAutoUpdateError.invalidEncoding
        }

        do {
            _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw HomebrewAutoUpdateError.invalidFormat(error.localizedDescription)
        }

        // Ensure LaunchAgents directory exists
        let launchAgentsDir = (plistPath as NSString).deletingLastPathComponent
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: launchAgentsDir) {
            try fileManager.createDirectory(atPath: launchAgentsDir,
                                           withIntermediateDirectories: true,
                                           attributes: nil)
        }

        // Write plist to LaunchAgents directory
        let plistURL = URL(fileURLWithPath: plistPath)
        try data.write(to: plistURL)

        // Verify file was written
        guard FileManager.default.fileExists(atPath: plistPath) else {
            throw HomebrewAutoUpdateError.fileWriteFailed
        }

        // Unregister old service (if exists) then register new one
        try? unregisterAgent(updateStatus: false)  // Don't update UI during re-registration

        // Register with launchctl
        let uid = getuid()
        let result = runTool("/bin/launchctl", arguments: ["bootstrap", "gui/\(uid)", plistPath])
        if result.exitCode != 0 {
            throw HomebrewAutoUpdateError.registrationFailed(result.stderr)
        }

        // Update state
        checkAgentStatus()
    }

    /// Unregister LaunchAgent
    /// - Parameter updateStatus: Whether to update isAgentLoaded state (default: true)
    func unregisterAgent(updateStatus: Bool = true) throws {
        let uid = getuid()
        let result = runTool("/bin/launchctl", arguments: ["bootout", "gui/\(uid)/\(label)"])
        // Note: bootout returns error if service not loaded, which is fine
        if result.exitCode != 0 && !result.stderr.contains("Could not find service") {
            throw HomebrewAutoUpdateError.registrationFailed(result.stderr)
        }

        // Only update status if requested (prevents UI flash during re-registration)
        if updateStatus {
            checkAgentStatus()
        }
    }

    /// Check if LaunchAgent is currently loaded
    func checkAgentStatus() {
        let uid = getuid()
        let result = runTool("/bin/launchctl", arguments: ["print", "gui/\(uid)/\(label)"])
        // If launchctl print succeeds, the service is loaded
        isAgentLoaded = (result.exitCode == 0)
    }

    /// Check if log file exists
    func checkLogFiles() {
        let fileManager = FileManager.default
        logFileExists = fileManager.fileExists(atPath: logPath)
    }

    /// Refresh state by reloading schedule from plist and checking agent status
    func refreshState() {
        loadSchedule()
        checkAgentStatus()
        checkLogFiles()
    }

    /// Remove all new schedules that haven't been saved to plist
    func removeUnsavedSchedules() {
        schedules.removeAll { schedule in
            // Remove if this schedule is NOT in originalSchedules (meaning it's new and unsaved)
            !originalSchedules.contains(where: { $0.id == schedule.id })
        }
    }

    /// Open log file in default text editor
    func openLogFile() {
        let url = URL(fileURLWithPath: logPath)
        NSWorkspace.shared.open(url)
    }

    /// Reload schedule from existing plist file (single source of truth)
    func loadSchedule() {
        let fileManager = FileManager.default

        // Only check regular plist path
        guard fileManager.fileExists(atPath: plistPath) else {
            schedules = []
            return
        }

        // Read and parse plist
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            printOS("Failed to read plist at \(plistPath)")
            schedules = []
            return
        }

        // Extract StartCalendarInterval array
        guard let calendarIntervals = plist["StartCalendarInterval"] as? [[String: Int]] else {
            schedules = []
            return
        }

        // The arguments are flags for the bundled, static runner script.
        if let programArgs = plist["ProgramArguments"] as? [String] {
            runUpdate = programArgs.contains("--update")
            runUpgrade = programArgs.contains("--upgrade")
            runCleanup = programArgs.contains("--cleanup")
        }

        // Parse each interval into ScheduleOccurrence
        schedules = calendarIntervals.compactMap { interval in
            let hour = interval["Hour"]
            let minute = interval["Minute"]

            guard let hour = hour, let minute = minute else {
                return nil
            }

            // Determine frequency by which keys exist
            if let day = interval["Day"] {
                // Monthly (has Day key)
                return ScheduleOccurrence(
                    frequency: .monthly,
                    dayOfMonth: day,
                    hour: hour,
                    minute: minute,
                    isEnabled: true
                )
            } else if let weekday = interval["Weekday"] {
                // Weekly (has Weekday key)
                return ScheduleOccurrence(
                    frequency: .weekly,
                    weekday: weekday,
                    hour: hour,
                    minute: minute,
                    isEnabled: true
                )
            } else {
                // Daily (only Hour and Minute, no Weekday or Day)
                return ScheduleOccurrence(
                    frequency: .daily,
                    hour: hour,
                    minute: minute,
                    isEnabled: true
                )
            }
        }

        // Store as original state after loading
        originalSchedules = schedules
        originalRunUpdate = runUpdate
        originalRunUpgrade = runUpgrade
        originalRunCleanup = runCleanup
    }

    // MARK: - Private Methods

    /// Execute a fixed executable with separately-delimited arguments.
    private func runTool(_ executable: String, arguments: [String]) -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let stdout = String(data: outputData, encoding: .utf8) ?? ""
            let stderr = String(data: errorData, encoding: .utf8) ?? ""

            return (stdout, stderr, process.terminationStatus)
        } catch {
            return ("", error.localizedDescription, -1)
        }
    }

    /// Generate plist XML from current schedules
    private func generatePlist() -> String {
        let enabledSchedules = schedules.filter { $0.isEnabled }

        let runnerPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/homebrew-auto-update.sh").path
        var runnerArguments = [runnerPath]
        if runUpdate { runnerArguments.append("--update") }
        if runUpgrade { runnerArguments.append("--upgrade") }
        if runCleanup { runnerArguments.append("--cleanup") }
        let programArguments = runnerArguments.map { "                <string>\($0.xmlEscaped)</string>" }
            .joined(separator: "\n")

        // Generate StartCalendarInterval entries
        let calendarIntervals = enabledSchedules.map { schedule in
            var dict = """
                    <dict>

            """

            // Add keys based on frequency
            switch schedule.frequency {
            case .daily:
                // Only Hour and Minute
                dict += """
                        <key>Hour</key>
                        <integer>\(schedule.hour)</integer>
                        <key>Minute</key>
                        <integer>\(schedule.minute)</integer>

                """
            case .weekly:
                // Weekday, Hour, Minute
                dict += """
                        <key>Weekday</key>
                        <integer>\(schedule.weekday ?? 0)</integer>
                        <key>Hour</key>
                        <integer>\(schedule.hour)</integer>
                        <key>Minute</key>
                        <integer>\(schedule.minute)</integer>

                """
            case .monthly:
                // Day, Hour, Minute
                dict += """
                        <key>Day</key>
                        <integer>\(schedule.dayOfMonth ?? 1)</integer>
                        <key>Hour</key>
                        <integer>\(schedule.hour)</integer>
                        <key>Minute</key>
                        <integer>\(schedule.minute)</integer>

                """
            }

            dict += """
                    </dict>
            """
            return dict
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
        \(programArguments)
            </array>
            <key>EnvironmentVariables</key>
            <dict>
                <key>PATH</key>
                <string>\((HomebrewController.shared.getBrewPrefix() + "/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin").xmlEscaped)</string>
                <key>SUDO_ASKPASS</key>
                <string>\((Bundle.main.bundlePath + "/Contents/Resources/askpass.sh").xmlEscaped)</string>
            </dict>
            <key>RunAtLoad</key>
            <false/>
            <key>StartCalendarInterval</key>
            <array>
        \(calendarIntervals)
            </array>
        </dict>
        </plist>
        """
    }
}

private extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - Error Types

enum HomebrewAutoUpdateError: LocalizedError {
    case invalidEncoding
    case invalidFormat(String)
    case fileWriteFailed
    case registrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Failed to encode plist content"
        case .invalidFormat(let details):
            return "Invalid plist format: \(details)"
        case .fileWriteFailed:
            return "Failed to write plist file to LaunchAgents directory"
        case .registrationFailed(let details):
            return "Failed to register LaunchAgent: \(details)"
        }
    }
}
