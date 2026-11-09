import AppKit
import SwiftUI
import SpriteKit

@main
struct VectorSwarmApp: App {
    var body: some Scene {
        WindowGroup("Vector Swarm") {
            SwarmWindow().preferredColorScheme(.dark)
                .frame(minWidth: 880, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 810)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

enum SwarmStyle: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case modern = "Modern"
    var id: String { rawValue }
}
enum SwarmDifficulty: String, CaseIterable, Identifiable {
    case rookie = "Rookie"
    case pilot = "Pilot"
    case ace = "Ace"
    var id: String { rawValue }
    var speed: CGFloat {
        switch self { case .rookie: return 0.76; case .pilot: return 1; case .ace: return 1.28 }
    }
}

struct SwarmSave: Codable {
    var score: Int
    var wave: Int
    var lives: Int
    var rescuedWingmen: Int
    var best: Int
}

@MainActor
final class SwarmSession: ObservableObject {
    @Published var style: SwarmStyle = .classic
    @Published var difficulty: SwarmDifficulty = .pilot
    @Published var sound = true
    let scene = SwarmScene(size: CGSize(width: 1100, height: 710))
    init() { scene.scaleMode = .aspectFit }
    func sync() {
        scene.style = style
        scene.difficulty = difficulty
        scene.soundEnabled = sound
        scene.refreshArtwork()
    }
}

struct SwarmWindow: View {
    @StateObject private var session = SwarmSession()
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: "sparkles.rectangle.stack")
                    .foregroundStyle(.cyan)
                Text("VECTOR SWARM")
                    .font(.system(size: 17, weight: .black, design: .monospaced))
                    .tracking(2)
                Spacer()
                Picker("Display", selection: $session.style) {
                    ForEach(SwarmStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 188)
                Picker("Threat", selection: $session.difficulty) {
                    ForEach(SwarmDifficulty.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 136)
                Toggle(isOn: $session.sound) {
                    Image(systemName: session.sound ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }.toggleStyle(.button).help("Arcade sound")
                Button("Save") { session.scene.save() }
                Button("Load") { session.scene.load() }
                Button("New Game") { session.scene.newGame() }
            }
            .padding(.horizontal, 20)
            .frame(height: 57)
            .background(Color(red: 0.035, green: 0.07, blue: 0.12))
            SpriteViewHost(scene: session.scene)
                .background(.black)
            HStack {
                Text("← → / A D MOVE     SPACE FIRE     P PAUSE     ENTER START")
                Spacer()
                Text("CLASSIC ARCADE  /  MODERN REMASTER")
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background(.black)
        }
        .onAppear { session.sync() }
        .onChange(of: session.style) { _ in session.sync() }
        .onChange(of: session.difficulty) { _ in session.sync() }
        .onChange(of: session.sound) { _ in session.sync() }
    }
}

struct SpriteViewHost: NSViewRepresentable {
    let scene: SwarmScene
    func makeNSView(context: Context) -> SwarmKeysView {
        let view = SwarmKeysView()
        view.sceneRef = scene
        view.preferredFramesPerSecond = 60
        view.presentScene(scene)
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }
    func updateNSView(_ view: SwarmKeysView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
    }
}
final class SwarmKeysView: SKView {
    weak var sceneRef: SwarmScene?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { DispatchQueue.main.async { self.window?.makeFirstResponder(self) } }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }
    override func keyDown(with event: NSEvent) {
        sceneRef?.key(event.keyCode, down: true, repeated: event.isARepeat)
    }
    override func keyUp(with event: NSEvent) {
        sceneRef?.key(event.keyCode, down: false, repeated: false)
    }
}

private final class Invader {
    var node: SKNode
    var baseX: CGFloat
    var baseY: CGFloat
    var kind: Int
    var diving = false
    var diveTime: TimeInterval = 0
    var origin = CGPoint.zero
    var shot = false
    init(node: SKNode, x: CGFloat, y: CGFloat, kind: Int) {
        self.node = node
        self.baseX = x
        self.baseY = y
        self.kind = kind
    }
}
private struct Shot {
    var node: SKShapeNode
    var enemy: Bool
    var velocity: CGVector
}

final class SwarmScene: SKScene {
    var style: SwarmStyle = .classic
    var difficulty: SwarmDifficulty = .pilot
    var soundEnabled = true
    private let saveKey = "VectorSwarm.Save.v1"
    private let highKey = "VectorSwarm.High.v1"
    private let player = SKNode()
    private let backdrop = SKNode()
    private let actorLayer = SKNode()
    private let hud = SKNode()
    private let overlay = SKNode()
    private var enemies: [Invader] = []
    private var shots: [Shot] = []
    private var particles: [SKNode] = []
    private var left = false, right = false, firing = false
    private var running = false, pausedGame = false, gameOver = false
    private var clock: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0
    private var lastFire: TimeInterval = -10
    private var lastDive: TimeInterval = 0
    private var lastEnemyFire: TimeInterval = 0
    private var invincibleUntil: TimeInterval = 0
    private var score = 0, wave = 1, lives = 3, best = 0, rescued = 0
    private var captured = false
    private var captureTimer: TimeInterval = 0
    private var banner = ""
    private var bannerUntil: TimeInterval = 0

    override func didMove(to view: SKView) {
        backgroundColor = .black
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        addChild(backdrop)
        addChild(actorLayer)
        addChild(hud)
        addChild(overlay)
        best = UserDefaults.standard.integer(forKey: highKey)
        newGame(autostart: false)
    }
    func key(_ code: UInt16, down: Bool, repeated: Bool) {
        switch code {
        case 123, 0: left = down
        case 124, 2: right = down
        case 49: firing = down
        case 36 where down && !repeated:
            if !running || gameOver { newGame() }
            else if pausedGame { pausedGame = false; updateOverlay() }
        case 35 where down && !repeated:
            if running && !gameOver { pausedGame.toggle(); updateOverlay() }
        default: break
        }
    }
    func newGame() { newGame(autostart: true) }
    private func newGame(autostart: Bool) {
        actorLayer.removeAllChildren()
        enemies.removeAll(); shots.removeAll(); particles.removeAll()
        score = 0; wave = 1; lives = 3; rescued = 0
        captured = false; gameOver = false; running = autostart
        pausedGame = false; clock = 0; lastUpdate = 0
        lastFire = -10; lastDive = 0; lastEnemyFire = 0
        invincibleUntil = 0; banner = ""; bannerUntil = 0
        player.position = CGPoint(x: 0, y: -275)
        actorLayer.addChild(player)
        spawnWave()
        refreshArtwork()
    }
    func save() {
        let record = SwarmSave(score: score, wave: wave, lives: lives,
                               rescuedWingmen: rescued, best: best)
        if let encoded = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
            showBanner("GAME SAVED")
        }
    }
    func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let saved = try? JSONDecoder().decode(SwarmSave.self, from: data) else {
            showBanner("NO SAVED GAME"); return
        }
        newGame()
        score = saved.score; wave = max(1, saved.wave); lives = max(1, saved.lives)
        rescued = saved.rescuedWingmen; best = max(best, saved.best)
        spawnWave(); showBanner("GAME RESTORED")
    }
    func refreshArtwork() {
        guard backdrop.parent != nil else { return }
        backdrop.removeAllChildren()
        let modern = style == .modern
        for i in 0..<125 {
            let x = CGFloat((i * 137 + 23) % 997) / 997 * 1060 - 530
            let y = CGFloat((i * 181 + 47) % 991) / 991 * 670 - 335
            let radius: CGFloat = i.isMultiple(of: 9) ? 1.55 : 0.62
            let star = SKShapeNode(circleOfRadius: radius)
            star.fillColor = .white.withAlphaComponent(modern ? 0.62 : 0.3)
            star.strokeColor = .clear
            star.position = CGPoint(x: x, y: y)
            backdrop.addChild(star)
        }
        if modern {
            for index in 0..<7 {
                let cloud = SKShapeNode(ellipseOf: CGSize(width: 370 + index * 39, height: 85 + index * 18))
                cloud.fillColor = NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.29, alpha: 0.035)
                cloud.strokeColor = .clear
                cloud.position = CGPoint(x: CGFloat(index * 130 - 390), y: CGFloat(index * 80 - 250))
                cloud.zPosition = -2
                backdrop.addChild(cloud)
            }
        }
        drawPlayer()
        for enemy in enemies { drawEnemy(enemy) }
        drawHUD()
        updateOverlay()
    }
    private func drawPlayer() {
        player.removeAllChildren()
        let modern = style == .modern
        let hull = SKShapeNode(path: polygon([
            CGPoint(x: 0, y: 29), CGPoint(x: -9, y: 6), CGPoint(x: -27, y: -12),
            CGPoint(x: -26, y: -23), CGPoint(x: -8, y: -15),
            CGPoint(x: 0, y: -21), CGPoint(x: 8, y: -15),
            CGPoint(x: 26, y: -23), CGPoint(x: 27, y: -12), CGPoint(x: 9, y: 6)
        ]))
        hull.fillColor = modern ? NSColor(calibratedRed: 0.12, green: 0.38, blue: 0.65, alpha: 1) : .clear
        hull.strokeColor = modern ? .cyan : .white
        hull.lineWidth = modern ? 2.3 : 1.6
        hull.glowWidth = modern ? 7 : 1
        player.addChild(hull)
        let canopy = SKShapeNode(ellipseOf: CGSize(width: 11, height: 24))
        canopy.fillColor = modern ? .cyan.withAlphaComponent(0.65) : .clear
        canopy.strokeColor = .cyan
        canopy.position.y = 2
        player.addChild(canopy)
        if rescued > 0 {
            for side in [-1, 1] {
                let wing = SKShapeNode(path: polygon([
                    CGPoint(x: 0, y: 12), CGPoint(x: -12, y: -9),
                    CGPoint(x: 0, y: -6), CGPoint(x: 12, y: -9)
                ]))
                wing.position = CGPoint(x: CGFloat(side) * 43, y: -4)
                wing.strokeColor = .cyan; wing.fillColor = .clear
                wing.glowWidth = modern ? 4 : 0
                player.addChild(wing)
            }
        }
    }
    private func polygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
    private func drawEnemy(_ enemy: Invader) {
        enemy.node.removeAllChildren()
        let modern = style == .modern
        let elite = enemy.kind == 2
        let wing: CGFloat = elite ? 24 : 19
        let path = polygon([
            CGPoint(x: 0, y: 11), CGPoint(x: -8, y: 8),
            CGPoint(x: -wing, y: 13), CGPoint(x: -wing + 4, y: -5),
            CGPoint(x: -8, y: -9), CGPoint(x: 0, y: -4),
            CGPoint(x: 8, y: -9), CGPoint(x: wing - 4, y: -5),
            CGPoint(x: wing, y: 13), CGPoint(x: 8, y: 8)
        ])
        let shape = SKShapeNode(path: path)
        let color: NSColor = elite ? .systemOrange : enemy.kind == 1 ? .systemPink : .systemCyan
        shape.fillColor = modern ? color.withAlphaComponent(0.55) : .clear
        shape.strokeColor = color
        shape.lineWidth = modern ? 2.1 : 1.4
        shape.glowWidth = modern ? 6 : 1
        enemy.node.addChild(shape)
        let core = SKShapeNode(circleOfRadius: elite ? 6 : 4)
        core.fillColor = color
        core.strokeColor = .white
        core.glowWidth = modern ? 8 : 1
        enemy.node.addChild(core)
    }
    private func spawnWave() {
        for enemy in enemies { enemy.node.removeFromParent() }
        enemies.removeAll()
        let columns = 10
        for row in 0..<4 {
            for column in 0..<columns {
                let x = CGFloat(column) * 76 - CGFloat(columns - 1) * 38
                let y = CGFloat(235 - row * 55)
                let node = SKNode()
                actorLayer.addChild(node)
                let enemy = Invader(node: node, x: x, y: y, kind: row == 0 ? 2 : row == 1 ? 1 : 0)
                node.position = CGPoint(x: x, y: y)
                enemies.append(enemy)
                drawEnemy(enemy)
            }
        }
        showBanner("WAVE \(wave)")
    }
    private func showBanner(_ text: String) {
        banner = text; bannerUntil = clock + 1.7
        drawHUD()
    }
    private func drawHUD() {
        hud.removeAllChildren()
        func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, alignment: SKLabelHorizontalAlignmentMode = .left) {
            let node = SKLabelNode(fontNamed: "Menlo-Bold")
            node.text = text; node.fontSize = size; node.fontColor = color
            node.horizontalAlignmentMode = alignment
            node.verticalAlignmentMode = .center
            node.position = CGPoint(x: x, y: y)
            hud.addChild(node)
        }
        let accent: NSColor = style == .modern ? .cyan : .white
        label("SCORE", x: -507, y: 320, size: 12, color: .gray)
        label("\(score)", x: -507, y: 291, size: 26, color: accent)
        label("HIGH SCORE", x: 0, y: 320, size: 12, color: .gray, alignment: .center)
        label("\(best)", x: 0, y: 293, size: 20, color: .white, alignment: .center)
        label("WAVE \(wave)", x: 507, y: 320, size: 15, color: .cyan, alignment: .right)
        label("SHIPS \(lives)", x: -507, y: -325, size: 15, color: .cyan)
        label("WINGMEN \(rescued)", x: 507, y: -325, size: 13, color: .systemOrange, alignment: .right)
        if clock < bannerUntil {
            label(banner, x: 0, y: 3, size: 26, color: .cyan, alignment: .center)
        }
    }
    private func updateOverlay() {
        overlay.removeAllChildren()
        let headline: String
        let subtitle: String
        if gameOver {
            headline = "GAME OVER"
            subtitle = "PRESS ENTER TO PLAY AGAIN"
        } else if !running {
            headline = "VECTOR SWARM"
            subtitle = "PRESS ENTER TO START  •  SPACE TO FIRE"
        } else if pausedGame {
            headline = "PAUSED"
            subtitle = "PRESS P TO RESUME"
        } else { return }
        let shade = SKShapeNode(rectOf: CGSize(width: 870, height: 240), cornerRadius: 20)
        shade.fillColor = NSColor(calibratedRed: 0.015, green: 0.04, blue: 0.08, alpha: 0.86)
        shade.strokeColor = .cyan.withAlphaComponent(0.45)
        shade.position.y = 0
        overlay.addChild(shade)
        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.fontSize = 48; title.text = headline
        title.fontColor = style == .modern ? .cyan : .white
        title.position.y = 24; overlay.addChild(title)
        let detail = SKLabelNode(fontNamed: "Menlo")
        detail.fontSize = 17; detail.text = subtitle
        detail.fontColor = .white.withAlphaComponent(0.8)
        detail.position.y = -34; overlay.addChild(detail)
    }
    override func update(_ currentTime: TimeInterval) {
        if lastUpdate == 0 { lastUpdate = currentTime; return }
        let dt = min(currentTime - lastUpdate, 0.05)
        lastUpdate = currentTime
        guard running && !pausedGame && !gameOver else { return }
        clock += dt
        let dir = (right ? 1.0 : 0.0) - (left ? 1.0 : 0.0)
        player.position.x = max(-470, min(470, player.position.x + CGFloat(dir) * 390 * dt))
        if firing && clock - lastFire > 0.19 { firePlayer(); lastFire = clock }
        updateEnemies(dt)
        updateShots(dt)
        checkCollisions()
        if clock > bannerUntil && !banner.isEmpty {
            banner = ""; drawHUD()
        }
        if enemies.isEmpty {
            wave += 1
            spawnWave(); drawHUD()
        }
        if captured && clock - captureTimer > 3.5 {
            captured = false
            showBanner("CAPTURED PILOT LOST")
        }
    }
    private func firePlayer() {
        for offset in (rescued > 0 ? [-12.0, 12.0] : [0.0]) {
            let node = SKShapeNode(rectOf: CGSize(width: 3, height: 17), cornerRadius: 1)
            node.fillColor = .cyan; node.strokeColor = .white
            node.glowWidth = style == .modern ? 7 : 1
            node.position = CGPoint(x: player.position.x + CGFloat(offset), y: player.position.y + 32)
            actorLayer.addChild(node)
            shots.append(Shot(node: node, enemy: false, velocity: CGVector(dx: 0, dy: 730)))
        }
        tone("Tink")
    }
    private func updateEnemies(_ dt: TimeInterval) {
        let drift = sin(clock * 0.75) * 46
        if clock - lastDive > max(0.60, 2.65 - Double(wave) * 0.12) / Double(difficulty.speed),
           let selected = enemies.filter({ !$0.diving }).randomElement() {
            selected.diving = true; selected.diveTime = 0
            selected.origin = selected.node.position
            selected.shot = false
            lastDive = clock
        }
        for enemy in enemies {
            if enemy.diving {
                enemy.diveTime += dt * Double(difficulty.speed)
                let t = enemy.diveTime
                let radius: CGFloat = 175
                let targetX = player.position.x
                enemy.node.position.x = enemy.origin.x + sin(t * 2.5) * radius + CGFloat(min(t / 3, 1)) * (targetX - enemy.origin.x) * 0.55
                enemy.node.position.y = enemy.origin.y - CGFloat(t * 185)
                enemy.node.zRotation = sin(t * 3) * 0.65
                if t > 1.35 && !enemy.shot {
                    enemy.shot = true
                    fireEnemy(from: enemy.node.position, aimed: true)
                    if enemy.kind == 2 && !captured && lives > 1 && Int.random(in: 0..<8) == 0 {
                        captureBeam(from: enemy.node.position)
                    }
                }
                if enemy.node.position.y < -385 {
                    enemy.diving = false; enemy.diveTime = 0; enemy.node.zRotation = 0
                }
            } else {
                enemy.node.position = CGPoint(x: enemy.baseX + CGFloat(drift),
                                               y: enemy.baseY + sin(clock * 2 + Double(enemy.baseX) / 90) * 6)
            }
        }
        if clock - lastEnemyFire > max(0.7, 2.4 - Double(wave) * 0.07) / Double(difficulty.speed),
           let enemy = enemies.randomElement() {
            fireEnemy(from: enemy.node.position, aimed: false)
            lastEnemyFire = clock
        }
    }
    private func fireEnemy(from position: CGPoint, aimed: Bool) {
        let node = SKShapeNode(circleOfRadius: 4)
        node.fillColor = .systemPink; node.strokeColor = .white
        node.glowWidth = style == .modern ? 8 : 1
        node.position = position; actorLayer.addChild(node)
        let xvel = aimed ? (player.position.x - position.x) * 0.25 : 0
        shots.append(Shot(node: node, enemy: true,
                          velocity: CGVector(dx: xvel, dy: -250 - CGFloat(wave * 10))))
    }
    private func captureBeam(from origin: CGPoint) {
        guard abs(origin.x - player.position.x) < 85 else { return }
        captured = true; captureTimer = clock
        let beam = SKShapeNode(path: polygon([
            CGPoint(x: -17, y: 0), CGPoint(x: 17, y: 0),
            CGPoint(x: 80, y: -360), CGPoint(x: -80, y: -360)
        ]))
        beam.fillColor = .cyan.withAlphaComponent(0.12)
        beam.strokeColor = .cyan.withAlphaComponent(0.8)
        beam.position = origin
        actorLayer.addChild(beam)
        beam.run(.sequence([.fadeOut(withDuration: 0.65), .removeFromParent()]))
        if abs(origin.x - player.position.x) < 48 && clock >= invincibleUntil {
            lives -= 1
            invincibleUntil = clock + 2
            showBanner("PILOT CAPTURED  •  RESCUE THE ACE")
            drawHUD()
            if lives <= 0 { endGame() }
        }
    }
    private func updateShots(_ dt: TimeInterval) {
        for index in shots.indices {
            shots[index].node.position.x += shots[index].velocity.dx * dt
            shots[index].node.position.y += shots[index].velocity.dy * dt
        }
        shots.removeAll { shot in
            if abs(shot.node.position.y) > 370 || abs(shot.node.position.x) > 550 {
                shot.node.removeFromParent(); return true
            }
            return false
        }
    }
    private func checkCollisions() {
        var removedShots = Set<ObjectIdentifier>()
        var killedEnemies = Set<ObjectIdentifier>()
        for shot in shots {
            let shotID = ObjectIdentifier(shot.node)
            if shot.enemy {
                if clock >= invincibleUntil &&
                   abs(shot.node.position.x - player.position.x) < 22 &&
                   abs(shot.node.position.y - player.position.y) < 24 {
                    removedShots.insert(shotID)
                    damagePlayer()
                }
            } else {
                for enemy in enemies where !killedEnemies.contains(ObjectIdentifier(enemy.node)) {
                    if abs(shot.node.position.x - enemy.node.position.x) < 23 &&
                       abs(shot.node.position.y - enemy.node.position.y) < 19 {
                        removedShots.insert(shotID)
                        killedEnemies.insert(ObjectIdentifier(enemy.node))
                        score += enemy.kind == 2 ? (enemy.diving ? 400 : 150)
                             : enemy.kind == 1 ? (enemy.diving ? 200 : 80)
                             : (enemy.diving ? 100 : 50)
                        if captured && enemy.kind == 2 && enemy.diving {
                            captured = false; rescued = 1
                            showBanner("WINGMAN RESCUED  •  DUAL FIRE")
                            drawPlayer()
                        }
                        burst(at: enemy.node.position, color: enemy.kind == 2 ? .systemOrange : .cyan)
                        tone("Pop")
                        break
                    }
                }
            }
        }
        for enemy in enemies where enemy.diving {
            if clock >= invincibleUntil &&
               abs(enemy.node.position.x - player.position.x) < 26 &&
               abs(enemy.node.position.y - player.position.y) < 24 {
                killedEnemies.insert(ObjectIdentifier(enemy.node))
                burst(at: enemy.node.position, color: .systemPink)
                damagePlayer()
            }
        }
        shots.removeAll { shot in
            if removedShots.contains(ObjectIdentifier(shot.node)) {
                shot.node.removeFromParent(); return true
            }
            return false
        }
        enemies.removeAll { enemy in
            if killedEnemies.contains(ObjectIdentifier(enemy.node)) {
                enemy.node.removeFromParent(); return true
            }
            return false
        }
        if score > best {
            best = score; UserDefaults.standard.set(best, forKey: highKey)
        }
        if !removedShots.isEmpty || !killedEnemies.isEmpty { drawHUD() }
    }
    private func damagePlayer() {
        guard clock >= invincibleUntil else { return }
        lives -= 1; rescued = 0
        invincibleUntil = clock + 2.1
        drawPlayer(); drawHUD()
        burst(at: player.position, color: .cyan)
        tone("Basso")
        player.run(.sequence([
            .repeat(.sequence([.fadeAlpha(to: 0.25, duration: 0.12),
                               .fadeAlpha(to: 1, duration: 0.12)]), count: 8),
            .fadeAlpha(to: 1, duration: 0)
        ]))
        if lives <= 0 { endGame() }
    }
    private func endGame() {
        gameOver = true; running = false
        UserDefaults.standard.set(best, forKey: highKey)
        updateOverlay()
    }
    private func burst(at point: CGPoint, color: NSColor) {
        for i in 0..<12 {
            let fragment = SKShapeNode(circleOfRadius: style == .modern ? 3 : 2)
            fragment.fillColor = color
            fragment.strokeColor = .clear
            fragment.position = point
            actorLayer.addChild(fragment)
            let angle = CGFloat(i) * .pi / 6
            fragment.run(.sequence([
                .group([.move(by: CGVector(dx: cos(angle) * 55, dy: sin(angle) * 55), duration: 0.36),
                        .fadeOut(withDuration: 0.36)]),
                .removeFromParent()
            ]))
        }
    }
    private func tone(_ name: String) {
        guard soundEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
