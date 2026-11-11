// Menu bar UI, 1-bit 8-bit style: left pan = goal weight, right pan = battery ore.
// Charging: shovel drops ore in. Discharging: shovel digs ore out.
import SwiftUI
import ServiceManagement

enum Mode { case charging, holding, discharging }

final class Model: ObservableObject {
    @Published var pct = 0
    @Published var target = readTarget()
    @Published var mode = Mode.holding
    @Published var installed = false
    @Published var error: String?
    private let smc = SMC()
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        pct = batteryPercent() ?? 0
        installed = FileManager.default.fileExists(atPath: plistPath)
        mode = smc?.adapterDisabled == true ? .discharging : isCharging() ? .charging : .holding
    }

    func save() {
        do { try writeTarget(target); error = nil } catch { self.error = "INSTALL SERVICE FIRST" }
    }

    // admin password prompt → run `Scale install|uninstall` as root
    func privileged(_ cmd: String) {
        guard let exe = Bundle.main.executablePath else { return }
        let esc = exe.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var err: NSDictionary?
        error = nil
        NSAppleScript(source: "do shell script quoted form of \"\(esc)\" & \" \(cmd)\" with administrator privileges")?
            .executeAndReturnError(&err)
        if let err, err[NSAppleScript.errorNumber] as? Int != -128 { error = err[NSAppleScript.errorMessage] as? String }
        target = readTarget()
        refresh()
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { self.error = error.localizedDescription }
            objectWillChange.send()
        }
    }
}

struct ScaleApp: App {
    @StateObject var model = Model()
    var body: some Scene {
        MenuBarExtra {
            Panel(model: model)
        } label: {
            Image(systemName: "scalemass.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Pixel grid

struct Pix {
    let w: Int, h: Int
    var on: [Bool]
    init(_ w: Int, _ h: Int) { self.w = w; self.h = h; on = Array(repeating: false, count: w * h) }

    mutating func set(_ x: Int, _ y: Int, _ v: Bool = true) {
        if x >= 0, y >= 0, x < w, y < h { on[y * w + x] = v }
    }
    mutating func rect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ v: Bool = true) {
        for j in 0..<max(rh, 0) { for i in 0..<max(rw, 0) { set(x + i, y + j, v) } }
    }
    mutating func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {  // Bresenham
        var x = x0, y = y0
        let dx = abs(x1 - x0), dy = -abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        while true {
            set(x, y)
            if x == x1 && y == y1 { return }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }
    mutating func sprite(_ rows: [String], _ x: Int, _ y: Int, _ v: Bool = true) {
        for (j, row) in rows.enumerated() { for (i, c) in row.enumerated() where c == "#" { set(x + i, y + j, v) } }
    }
    // 3x5 font, 1px spacing. cx = center x
    mutating func text(_ s: String, cx: Int, y: Int, _ v: Bool = true) {
        var x = cx - (s.count * 4 - 1) / 2
        for ch in s { sprite(font[ch] ?? [], x, y, v); x += 4 }
    }
}

let font: [Character: [String]] = [
    "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["###", "..#", "###", "#..", "###"], "3": ["###", "..#", "###", "..#", "###"],
    "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "###", "..#", "###"],
    "6": ["###", "#..", "###", "#.#", "###"], "7": ["###", "..#", "..#", "..#", "..#"],
    "8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "###"],
    "%": ["#.#", "..#", ".#.", "#..", "#.#"],
    "A": [".#.", "#.#", "###", "#.#", "#.#"], "C": ["###", "#..", "#..", "#..", "###"],
    "E": ["###", "#..", "##.", "#..", "###"], "G": ["###", "#..", "#.#", "#.#", "###"],
    "L": ["#..", "#..", "#..", "#..", "###"], "O": ["###", "#.#", "#.#", "#.#", "###"],
    "S": ["###", "#..", "###", "..#", "###"],
]

struct PixelCanvas: View {
    let pix: Pix
    var px: CGFloat = 3
    var body: some View {
        Canvas { c, _ in
            var p = Path()
            for y in 0..<pix.h { for x in 0..<pix.w where pix.on[y * pix.w + x] {
                p.addRect(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px))
            } }
            c.fill(p, with: .foreground)
        }
        .frame(width: CGFloat(pix.w) * px, height: CGFloat(pix.h) * px)
    }
}

// MARK: - Panel

struct Panel: View {
    @ObservedObject var model: Model

    var status: String {
        guard model.installed else { return "NOT INSTALLED" }
        switch model.mode {
        case .charging: return "> CHARGING"
        case .discharging: return "> DISCHARGING"
        case .holding: return "> HOLDING"
        }
    }

    var title: Pix { var g = Pix(19, 5); g.text("SCALE", cx: 9, y: 0); return g }
    var dashes: Pix { var g = Pix(92, 1); for x in stride(from: 0, to: 92, by: 2) { g.set(x, 0) }; return g }

    func step(_ d: Int) { model.target = clampTarget(model.target + d); model.save() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PixelCanvas(pix: title)
                Spacer()
                Text(status)
            }
            ScaleView(pct: model.pct, target: model.target, mode: model.installed ? model.mode : .holding)

            VStack(spacing: 6) {
                HStack {
                    Text("GOAL")
                    Spacer()
                    Button("[-]") { step(-1) }
                    Text(model.target >= 100 ? "NO LIMIT" : "\(model.target)%").frame(width: 64)
                    Button("[+]") { step(1) }
                }
                PixelBar(value: $model.target, onCommit: model.save)
            }

            if let e = model.error { Text("! " + e.uppercased()) }

            PixelCanvas(pix: dashes)
            HStack {
                Button((model.launchAtLogin ? "[x]" : "[ ]") + " AUTOSTART") { model.launchAtLogin.toggle() }
                Spacer()
                Button(model.installed ? "[UNINSTALL]" : "[INSTALL]") {
                    model.privileged(model.installed ? "uninstall" : "install")
                }
                Button("[QUIT]") { try? writeTarget(100); NSApp.terminate(nil) }  // 앱 종료 = 제한 해제
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .bold, design: .monospaced))
        .foregroundStyle(.primary)
        .padding(16)
        .frame(width: 308)
        .onAppear(perform: model.refresh)
    }
}

// Segmented pixel slider, 20...100
struct PixelBar: View {
    @Binding var value: Int
    let onCommit: () -> Void

    var body: some View {
        var g = Pix(92, 7)
        g.rect(0, 0, 92, 1); g.rect(0, 6, 92, 1); g.rect(0, 0, 1, 7); g.rect(91, 0, 1, 7)
        let filled = (value - 20) * 88 / 80
        for x in 0..<filled where x % 3 != 2 { g.rect(2 + x, 2, 1, 3) }
        return PixelCanvas(pix: g)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value = clampTarget(20 + Int(($0.location.x / 276 * 80).rounded())) }
                .onEnded { _ in onCommit() })
    }
}

// MARK: - Scale scene (92×64 px @3pt, 8 fps)

struct ScaleView: View {
    let pct: Int, target: Int, mode: Mode

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.125)) { ctx in
            PixelCanvas(pix: scene(Int(ctx.date.timeIntervalSinceReferenceDate * 8)))
        }
    }

    var ores: Int { min(10, max(0, (pct + 5) / 10)) }

    static let ore = [".##.", "##.#", "####", ".##."]
    static let shovel = ["......##", ".....##.", "....##..", ".####...", "#####...", "####....", ".##....."]
    static let face = [".#####.", "#######", "#######", "#######", "#######", "#######", ".#####."]

    // top-left of ore sprite i in a 4-3-2-1 pyramid sitting on pan at hook (ex, ey)
    func orePos(_ i: Int, _ ex: Int, _ ey: Int) -> (Int, Int) {
        var i = i, r = 0
        while i >= 4 - r && r < 3 { i -= 4 - r; r += 1 }
        let off = (Double(i) - Double(3 - r) / 2) * 5
        return (ex - 2 + Int(off.rounded(.down)), ey + 22 - 4 - r * 4)
    }

    func scene(_ f: Int) -> Pix {
        var g = Pix(92, 64)
        let cx = 46, cy = 16
        let th = max(-14, min(14, Double(pct - target) * 0.7)) * .pi / 180  // ore heavier → right side down
        let dx = Int((30 * cos(th)).rounded()), dy = Int((30 * sin(th)).rounded())
        let (lx, ly, rx, ry) = (cx - dx, cy - dy, cx + dx, cy + dy)

        // stand
        g.rect(30, 61, 32, 2); g.rect(34, 59, 24, 2); g.rect(45, cy, 2, 59 - cy)
        // beam
        g.line(lx, ly, rx, ry); g.line(lx, ly + 1, rx, ry + 1)

        for (ex, ey) in [(lx, ly), (rx, ry)] {
            g.rect(ex - 1, ey - 1, 3, 3)
            g.line(ex, ey + 1, ex - 11, ey + 21); g.line(ex, ey + 1, ex + 11, ey + 21)
            g.rect(ex - 12, ey + 22, 25, 1); g.rect(ex - 11, ey + 23, 23, 1); g.rect(ex - 9, ey + 24, 19, 1)
        }

        // left: goal weight with number cut out
        let wb = ly + 22
        g.sprite([".###.", "#...#"], lx - 2, wb - 11)
        g.rect(lx - 7, wb - 9, 15, 9); g.set(lx - 7, wb - 9, false); g.set(lx + 7, wb - 9, false)
        g.text("\(target)", cx: lx, y: wb - 7, false)
        g.text("GOAL", cx: lx, y: wb + 4)

        // right: ore pile
        for i in 0..<ores { let (x, y) = orePos(i, rx, ry); g.sprite(Self.ore, x, y) }
        g.text("\(pct)%", cx: rx, y: ry + 26)

        // shovel + flying ore, 12-frame loop
        let t = f % 12
        let blade = (rx + 4, ry + 7)
        func lerp(_ a: Int, _ b: Int, _ q: Double) -> Int { a + Int((Double(b - a) * q).rounded()) }
        var dip = false
        switch mode {
        case .charging:
            dip = (3...4).contains(t)
            if (3...9).contains(t) {
                let q = Double(t - 3) / 6, s = orePos(min(ores, 9), rx, ry)
                g.sprite(Self.ore, lerp(blade.0, s.0, q), lerp(blade.1, s.1, q * q))
            }
        case .discharging:
            dip = t <= 1
            if t <= 5 {
                let q = Double(t) / 5, s = orePos(max(ores - 1, 0), rx, ry)
                g.sprite(Self.ore, lerp(s.0, blade.0, q), lerp(s.1, blade.1, 1 - (1 - q) * (1 - q)))
            } else if t % 2 == 0 {  // blink away
                let q = Double(t - 6) / 5
                g.sprite(Self.ore, blade.0 + Int(q * 12), blade.1 - Int(sin(q * .pi * 0.8) * 10))
            }
        case .holding:
            if f % 16 < 8 { g.sprite([".#.", "###", ".#."], cx + 6, cy - 9) }  // sparkle
        }
        g.sprite(Self.shovel, rx + 5 - (dip ? 1 : 0), ry + 3 + (dip ? 1 : 0))

        // face on pivot
        g.sprite(Self.face, cx - 3, cy - 3)
        let blink = mode == .holding || f % 24 == 0
        if blink { for x in [1, 2, 4, 5] { g.set(cx - 3 + x, cy - 1, false) } }
        else { g.set(cx - 1, cy - 1, false); g.set(cx + 1, cy - 1, false) }
        if mode == .discharging { g.set(cx, cy + 1, false); g.set(cx, cy + 2, false) }   // o
        else { g.set(cx - 1, cy + 1, false); g.set(cx, cy + 2, false); g.set(cx + 1, cy + 1, false) }  // ᴗ
        return g
    }
}
