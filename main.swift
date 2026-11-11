// Scale — 배터리 충전량을 목표치에 맞춰 유지 (Apple Silicon 전용)
//   Scale.app 실행          메뉴바 UI (App.swift)
//   scale                   현재 상태
//   scale 80                목표 80% (100 = 제한 해제)
//   sudo scale install      서비스 설치 / sudo scale uninstall 제거
//   scale daemon            LaunchDaemon이 root로 실행
//   scale selftest          로직 체크
import Foundation
import IOKit
import IOKit.ps

let targetFile = "/Library/Application Support/Scale/target"
let plistPath = "/Library/LaunchDaemons/com.scale.daemon.plist"
let helperPath = "/Library/PrivilegedHelperTools/com.scale.daemon"  // root 소유 복사본 (사용자 쓰기 불가)
let interval: TimeInterval = 10  // 확인 주기(초)

// MARK: - SMC (raw 80바이트 SMCKeyData_t, 오프셋 직접 접근)

final class SMC {
    private var conn: io_connect_t = 0

    init?() {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        guard IOServiceOpen(svc, mach_task_self_, 0, &conn) == kIOReturnSuccess else { return nil }
    }

    private func call(_ key: String, cmd: UInt8, size: UInt32 = 0, bytes: [UInt8] = []) -> [UInt8]? {
        var inp = [UInt8](repeating: 0, count: 80), out = inp
        var k: UInt32 = 0
        for c in key.utf8 { k = k << 8 | UInt32(c) }
        withUnsafeBytes(of: k) { inp.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: size) { inp.replaceSubrange(28..<32, with: $0) }
        inp[42] = cmd
        inp.replaceSubrange(48..<48 + bytes.count, with: bytes)
        var outSize = 80
        let r = IOConnectCallStructMethod(conn, 2, inp, 80, &out, &outSize)
        guard r == kIOReturnSuccess, out[40] == 0 else { return nil }
        return out
    }

    private func size(_ key: String) -> UInt32? {
        call(key, cmd: 9).map { o in o[28..<32].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
    }

    func read(_ key: String) -> [UInt8]? {
        guard let n = size(key), let o = call(key, cmd: 5, size: n) else { return nil }
        return Array(o[48..<48 + Int(n)])
    }

    @discardableResult
    func write(_ key: String, _ bytes: [UInt8]) -> Bool {
        call(key, cmd: 6, size: UInt32(bytes.count), bytes: bytes) != nil
    }

    func has(_ key: String) -> Bool { size(key) != nil }

    // 펌웨어별 키: 신형(macOS 15+) CHTE/CHIE, 구형 CH0B·CH0C/CH0I
    func setCharging(_ on: Bool) {
        if has("CHTE") { write("CHTE", on ? [0, 0, 0, 0] : [1, 0, 0, 0]) }
        else { write("CH0B", [on ? 0 : 2]); write("CH0C", [on ? 0 : 2]) }
    }

    func setAdapter(_ on: Bool) {  // off = 어댑터 꽂혀 있어도 배터리로 구동(방전)
        if has("CHIE") { write("CHIE", [on ? 0 : 8]) }
        else { write("CH0I", [on ? 0 : 1]) }
    }

    var adapterDisabled: Bool { (read("CHIE") ?? read("CH0I"))?.first.map { $0 != 0 } ?? false }
}

// MARK: - 배터리

func powerSource() -> [String: Any]? {
    let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
    return list.lazy.compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }.first
}

func batteryPercent() -> Int? {
    guard let d = powerSource(), let cur = d[kIOPSCurrentCapacityKey] as? Int,
          let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { return nil }
    return cur * 100 / max
}

func isCharging() -> Bool { powerSource()?[kIOPSIsChargingKey] as? Bool ?? false }

// 어댑터를 SMC로 끊어도 물리적으로 꽂혀 있으면 non-nil
func adapterPlugged() -> Bool { IOPSCopyExternalPowerAdapterDetails() != nil }

// MARK: - 로직

struct Action: Equatable { var charge: Bool; var adapter: Bool }

func decide(pct: Int, target: Int) -> Action {
    if target >= 100 || pct < target { return Action(charge: true, adapter: true) }   // 79 → 충전
    if pct == target { return Action(charge: false, adapter: true) }                  // 80 → 유지
    return Action(charge: false, adapter: false)                                      // 100 → 방전
}

func clampTarget(_ t: Int) -> Int { min(max(t, 20), 100) }

func readTarget() -> Int {
    let s = (try? String(contentsOfFile: targetFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    return s.flatMap(Int.init).map(clampTarget) ?? 100
}

// 파일은 install 시 666으로 생성 → 앱/CLI가 sudo 없이 씀 (atomic 쓰기는 디렉터리 권한이 필요해서 안 씀)
func writeTarget(_ t: Int) throws {
    try "\(clampTarget(t))\n".write(toFile: targetFile, atomically: false, encoding: .utf8)
}

func run(_ path: String, _ args: String...) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardError = FileHandle.nullDevice
    try? p.run(); p.waitUntilExit()
}

// MARK: - 데몬

func daemon() {
    guard let smc = SMC() else { fatalError("cannot open AppleSMC") }
    var noSleep = false

    func restore() {
        smc.setCharging(true); smc.setAdapter(true)
        if noSleep { run("/usr/bin/pmset", "-a", "disablesleep", "0") }
        exit(0)
    }
    signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN)
    for s in [SIGTERM, SIGINT] {
        let src = DispatchSource.makeSignalSource(signal: s, queue: .main)
        src.setEventHandler(handler: restore); src.resume()
        _ = Unmanaged.passRetained(src)  // 프로세스 수명 동안 유지
    }

    Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
        guard let pct = batteryPercent() else { return }
        let a = decide(pct: pct, target: readTarget())
        // 매번 씀: 잠자기/깨어남 후 펌웨어가 값을 리셋해도 다시 맞춤
        smc.setCharging(a.charge); smc.setAdapter(a.adapter)
        // 크림쉘(뚜껑 닫힘)에서 배터리 구동 = 잠자기 → 방전 중에만 잠자기 차단.
        // 어댑터가 실제로 빠져 있으면 차단 안 함(가방 속 과열 방지).
        let wantNoSleep = !a.adapter && adapterPlugged()
        if wantNoSleep != noSleep {
            run("/usr/bin/pmset", "-a", "disablesleep", wantNoSleep ? "1" : "0")
            noSleep = wantNoSleep
        }
    }.fire()
    RunLoop.main.run()
}

// MARK: - 설치 (root)

func install() {
    let fm = FileManager.default
    guard let exe = Bundle.main.executablePath else { exit(1) }
    try? fm.createDirectory(atPath: (targetFile as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    if !fm.fileExists(atPath: targetFile) { try? writeTarget(80) }
    chmod(targetFile, 0o666)

    run("/bin/launchctl", "bootout", "system", plistPath)  // 기존 데몬 정지(SIGTERM → 원상복구)
    try? fm.createDirectory(atPath: (helperPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try? fm.removeItem(atPath: helperPath)
    try! fm.copyItem(atPath: exe, toPath: helperPath)
    run("/usr/bin/codesign", "-s", "-", "-f", helperPath)  // 번들 밖 단독 실행용 재서명
    // root 데몬 바이너리는 반드시 root 소유 — 사용자 쓰기 가능하면 권한 상승 구멍
    try! fm.setAttributes([.ownerAccountID: 0, .groupOwnerAccountID: 0, .posixPermissions: 0o755], ofItemAtPath: helperPath)

    let plist: [String: Any] = ["Label": "com.scale.daemon", "ProgramArguments": [helperPath, "daemon"],
                                "RunAtLoad": true, "KeepAlive": true]
    try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: URL(fileURLWithPath: plistPath))
    run("/bin/launchctl", "bootstrap", "system", plistPath)

    try? fm.createDirectory(atPath: "/usr/local/bin", withIntermediateDirectories: true)
    try? fm.removeItem(atPath: "/usr/local/bin/scale")
    try? fm.createSymbolicLink(atPath: "/usr/local/bin/scale", withDestinationPath: helperPath)
    print("installed (goal \(readTarget())%)")
}

func uninstall() {
    run("/bin/launchctl", "bootout", "system", plistPath)
    for p in [plistPath, helperPath, "/usr/local/bin/scale", (targetFile as NSString).deletingLastPathComponent] {
        try? FileManager.default.removeItem(atPath: p)
    }
    run("/usr/bin/pmset", "-a", "disablesleep", "0")
    print("uninstalled")
}

// MARK: - main

let cliArgs = CommandLine.arguments.dropFirst()
switch cliArgs.first {
case "daemon": daemon()
case "install": install()
case "uninstall": uninstall()
case "selftest":
    // precondition, not assert: assert is stripped in -O builds
    let charge = Action(charge: true, adapter: true), hold = Action(charge: false, adapter: true)
    let drain = Action(charge: false, adapter: false)
    precondition(decide(pct: 100, target: 80) == drain)
    precondition(decide(pct: 81, target: 80) == drain)
    precondition(decide(pct: 80, target: 80) == hold)
    precondition(decide(pct: 79, target: 80) == charge)
    precondition(decide(pct: 70, target: 80) == charge)
    precondition(decide(pct: 100, target: 100) == charge)
    precondition(decide(pct: 0, target: 20) == charge)
    precondition(decide(pct: 20, target: 20) == hold)
    precondition(clampTarget(5) == 20 && clampTarget(150) == 100 && clampTarget(55) == 55)
    print("ok")
case let n? where Int(n) != nil:
    do { try writeTarget(Int(n)!); print("goal: \(readTarget())%") }
    catch { print("service not installed: sudo scale install"); exit(1) }
case nil where Bundle.main.bundlePath.hasSuffix(".app"):
    ScaleApp.main()
default:
    let smc = SMC()
    let keys = ["CHTE", "CHIE", "CH0B", "CH0C", "CH0I"].filter { smc?.has($0) ?? false }
    print("battery: \(batteryPercent().map { "\($0)%" } ?? "?")  goal: \(readTarget())%  adapter: \(adapterPlugged() ? "plugged" : "none")  charging: \(isCharging())")
    print("SMC keys: \(keys.joined(separator: " "))")
    for k in keys { print("  \(k) = \(smc?.read(k)?.map { String(format: "%02x", $0) }.joined() ?? "?")") }
}
