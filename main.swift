// Mute on screen lock and restore sound on unlock.
//
// Usage:
//   lock-mute            Run as a daemon. Wait for screen lock and unlock.
//   lock-mute mute       Mute the default output now, then exit.
//   lock-mute unmute     Unmute the default output now, then exit.
//   lock-mute status     Print "muted", "unmuted", or "unsupported", then exit.

import CoreAudio
import CoreGraphics
import Foundation
import os

let log = Logger(subsystem: "local.lock-mute", category: "daemon")

func address(_ selector: AudioObjectPropertySelector,
             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
             element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

func defaultOutputDevice() -> AudioDeviceID? {
    var device = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
    let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
    return err == noErr && device != kAudioObjectUnknown ? device : nil
}

/// The output elements that have a mute control that can be set.
/// Most devices have one control on the main element. Some have one for each channel.
func muteElements(of device: AudioDeviceID) -> [AudioObjectPropertyElement] {
    func settable(_ element: AudioObjectPropertyElement) -> Bool {
        var addr = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, element: element)
        var isSettable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &addr)
            && AudioObjectIsPropertySettable(device, &addr, &isSettable) == noErr
            && isSettable.boolValue
    }
    if settable(kAudioObjectPropertyElementMain) { return [kAudioObjectPropertyElementMain] }

    var channels: [UInt32] = [1, 2]
    var size = UInt32(MemoryLayout<UInt32>.size * 2)
    var addr = address(kAudioDevicePropertyPreferredChannelsForStereo, scope: kAudioDevicePropertyScopeOutput)
    _ = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &channels)
    return channels.filter(settable)
}

func muteState(of device: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool? {
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var addr = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, element: element)
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
    return value != 0
}

func setMuted(_ muted: Bool, on device: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool {
    var value: UInt32 = muted ? 1 : 0
    var addr = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, element: element)
    return AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
}

func isMuted(_ device: AudioDeviceID) -> Bool? {
    let elements = muteElements(of: device)
    guard !elements.isEmpty else { return nil }
    return elements.allSatisfy { muteState(of: device, element: $0) == true }
}

/// Returns false if the device has no mute control or refuses the change.
func setMuted(_ muted: Bool, on device: AudioDeviceID) -> Bool {
    let elements = muteElements(of: device)
    guard !elements.isEmpty else { return false }
    var ok = true
    for element in elements {
        if !setMuted(muted, on: device, element: element) { ok = false }
    }
    return ok
}

func deviceName(_ device: AudioDeviceID) -> String {
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var addr = address(kAudioObjectPropertyName)
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &name) == noErr, let name else { return "device \(device)" }
    return name.takeRetainedValue() as String
}

@discardableResult
func apply(muted: Bool, reason: String) -> Bool {
    guard let device = defaultOutputDevice() else {
        log.notice("\(reason, privacy: .public): no default output device")
        return false
    }
    let name = deviceName(device)
    let ok = setMuted(muted, on: device)
    if ok {
        log.notice("\(reason, privacy: .public): \(muted ? "muted" : "unmuted", privacy: .public) \(name, privacy: .public)")
    } else {
        log.error("\(reason, privacy: .public): \(name, privacy: .public) has no mute control that can be set")
    }
    return ok
}

func screenIsLocked() -> Bool {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
}

switch CommandLine.arguments.dropFirst().first {
case "mute":
    exit(apply(muted: true, reason: "command") ? 0 : 1)
case "unmute":
    exit(apply(muted: false, reason: "command") ? 0 : 1)
case "status":
    let muted = defaultOutputDevice().flatMap(isMuted)
    print(muted.map { $0 ? "muted" : "unmuted" } ?? "unsupported")
    exit(muted == nil ? 1 : 0)
case nil:
    break
case let other?:
    FileHandle.standardError.write(Data("unknown command: \(other)\nusage: lock-mute [mute|unmute|status]\n".utf8))
    exit(64)
}

var lockedOutput: (device: AudioDeviceID, elementsToRestore: [AudioObjectPropertyElement])?

func muteForLock(reason: String) {
    guard lockedOutput == nil else { return }
    guard let device = defaultOutputDevice() else {
        log.notice("\(reason, privacy: .public): no default output device")
        return
    }

    let elements = muteElements(of: device)
    var elementsToRestore: [AudioObjectPropertyElement] = []
    var failed = elements.isEmpty
    for element in elements {
        let previous = muteState(of: device, element: element)
        if previous == true { continue }
        if setMuted(true, on: device, element: element) {
            if previous == false { elementsToRestore.append(element) }
        } else {
            failed = true
        }
    }
    lockedOutput = (device, elementsToRestore)
    if failed {
        log.error("\(reason, privacy: .public): could not mute \(deviceName(device), privacy: .public)")
    } else {
        log.notice("\(reason, privacy: .public): muted \(deviceName(device), privacy: .public)")
    }
}

func restoreOnUnlock() {
    guard let output = lockedOutput else { return }
    lockedOutput = nil
    guard !output.elementsToRestore.isEmpty else { return }

    var failed = false
    for element in output.elementsToRestore {
        if !setMuted(false, on: output.device, element: element) { failed = true }
    }
    if failed {
        log.error("screen unlocked: could not restore sound on \(deviceName(output.device), privacy: .public)")
    } else {
        log.notice("screen unlocked: restored sound on \(deviceName(output.device), privacy: .public)")
    }
}

let testPrefix = ProcessInfo.processInfo.environment["LOCK_MUTE_TEST_NOTIFICATION_PREFIX"]
let lockNotification = testPrefix.map { "\($0).lock" } ?? "com.apple.screenIsLocked"
let unlockNotification = testPrefix.map { "\($0).unlock" } ?? "com.apple.screenIsUnlocked"
let notifications = DistributedNotificationCenter.default()

let lockObserver = notifications.addObserver(
    forName: Notification.Name(lockNotification), object: nil, queue: .main
) { _ in
    muteForLock(reason: "screen locked")
}
let unlockObserver = notifications.addObserver(
    forName: Notification.Name(unlockNotification), object: nil, queue: .main
) { _ in
    restoreOnUnlock()
}

log.notice("waiting for \(lockNotification, privacy: .public) and \(unlockNotification, privacy: .public)")
if testPrefix == nil && screenIsLocked() {
    muteForLock(reason: "screen already locked at start")
}

withExtendedLifetime((lockObserver, unlockObserver)) { RunLoop.main.run() }
