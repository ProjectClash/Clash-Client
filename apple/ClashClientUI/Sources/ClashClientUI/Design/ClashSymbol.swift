import SwiftUI

 
 
 
 
 
public enum ClashSymbol: String, CaseIterable, Sendable {
     
    case appBadgeCheckmarkFill = "app.badge.checkmark.fill"
    case arrowClockwise = "arrow.clockwise"
    case arrowClockwiseIcloud = "arrow.clockwise.icloud"
    case arrowDown = "arrow.down"
    case arrowDownLeftAndArrowUpRight = "arrow.down.left.and.arrow.up.right"
    case arrowLeftArrowRight = "arrow.left.arrow.right"
    case arrowRight = "arrow.right"
    case profileClipboard = "list.clipboard"
    case proxyDomain = "slider.horizontal.below.square.and.square.filled"
    case ruleDomain = "clash.route.start"
    case dnsDomain = "clash.dns"
    case arrowTriangle2Circlepath = "arrow.triangle.2.circlepath"
    case arrowTriangleBranch = "arrow.triangle.branch"
     
     
     
     
    case arrowTriangleMerge = "arrow.triangle.merge"
     
    case arrowLeftAndRight = "arrow.left.and.right"
     
    case arrowLeftAndRightSquareFill = "arrow.left.and.right.square.fill"
    case arrowTriangleSwap = "arrow.triangle.swap"
    case arrowUp = "arrow.up"
    case arrowUpRightAndArrowDownLeft = "arrow.up.right.and.arrow.down.left"
    case arrowUpArrowDown = "arrow.up.arrow.down"
    case arrowUpArrowDownCircle = "arrow.up.arrow.down.circle"
    case arrowLeftToLine = "arrow.left.to.line"
    case arrowRightToLine = "arrow.right.to.line"
    case arrowUturnBackward = "arrow.uturn.backward"
    case arrowUturnForward = "arrow.uturn.forward"
    case bolt = "bolt"
    case boltHorizontal = "bolt.horizontal"
    case boltHorizontalCircle = "bolt.horizontal.circle"
    case boltSlash = "bolt.slash"
    case briefcaseCircleFill = "briefcase.circle.fill"
    case catCircleFill = "clash.cat.circle.fill"
    case checkmark = "checkmark"
    case checkmarkCircle = "checkmark.circle"
    case checkmarkCircleFill = "checkmark.circle.fill"
    case checkmarkShieldFill = "checkmark.shield.fill"
    case checklist = "checklist"
    case chevronBackward = "chevron.backward"
    case chevronDown = "chevron.down"
    case chevronForward = "chevron.forward"
    case chevronUp = "chevron.up"
    case chevronUpChevronDown = "chevron.up.chevron.down"
    case circle = "circle"
    case circleLefthalfFilled = "circle.lefthalf.filled"
    case clock = "clock"
    case cpu = "cpu"
    case cubeFill = "cube.fill"
    case curlybraces = "curlybraces"
    case docBadgePlus = "doc.badge.plus"
    case docOnClipboard = "doc.on.clipboard"
    case docOnDoc = "doc.on.doc"
    case docText = "doc.text"
    case docTextMagnifyingglass = "doc.text.magnifyingglass"
    case ellipsis = "ellipsis"
    case ellipsisCircle = "ellipsis.circle"
    case ellipsisCircleFill = "ellipsis.circle.fill"
    case exclamationmarkBubble = "exclamationmark.bubble"
    case exclamationmarkOctagon = "exclamationmark.octagon"
    case exclamationmarkShieldFill = "exclamationmark.shield.fill"
    case exclamationmarkTriangle = "exclamationmark.triangle"
    case exclamationmarkTriangleFill = "exclamationmark.triangle.fill"
    case externaldrive = "externaldrive"
    case eye = "eye"
    case eyeSlash = "eye.slash"
    case gaugeWithDotsNeedle33Percent = "gauge.with.dots.needle.33percent"
    case gearshape = "gearshape"
    case gearshape2 = "gearshape.2"
    case globe = "globe"
     
    case globeBadgeChevronBackward = "globe.badge.chevron.backward"
    case globeAsiaAustralia = "globe.asia.australia"
    case handRaisedFill = "hand.raised.fill"
     
    case scope = "scope"
     
    case starFill = "star.fill"
    case houseFill = "house.fill"
     
    case bookClosed = "book.closed"
    case icloudAndArrowDown = "icloud.and.arrow.down"
    case icloudAndArrowUp = "icloud.and.arrow.up"
    case infoCircle = "info.circle"
    case infoCircleFill = "info.circle.fill"
    case key = "key"
    case line3Horizontal = "line.3.horizontal"
    case line3HorizontalDecrease = "line.3.horizontal.decrease"
    case link = "link"
    case listBullet = "list.bullet"
    case listBulletIndent = "list.bullet.indent"
    case listBulletRectangle = "list.bullet.rectangle"
    case listBulletRectanglePortrait = "list.bullet.rectangle.portrait"
    case listTriangle = "list.triangle"
    case lockShield = "lock.shield"
    case keyboardChevronCompactDown = "keyboard.chevron.compact.down"
    case magnifyingglass = "magnifyingglass"
    case map = "map"
    case memorychip = "memorychip"
    case minusCircle = "minus.circle"
    case network = "network"
    case networkSlash = "network.slash"
    case pause = "pause"
    case pauseCircle = "pause.circle"
    case pauseCircleFill = "pause.circle.fill"
    case paperplane = "paperplane"
    case pencil = "pencil"
    case arrowUpDocument = "arrow.up.document"
    case pencilLine = "pencil.line"
    case person2 = "person.2"
    case photo = "photo"
    case play = "play"
    case playFill = "play.fill"
    case plus = "plus"
    case plusCircle = "plus.circle"
    case plusCircleFill = "plus.circle.fill"
    case point3ConnectedTrianglepathDotted = "point.3.connected.trianglepath.dotted"
    case point3FilledConnectedTrianglepathDotted = "point.3.filled.connected.trianglepath.dotted"
    case power = "power"
    case qrcodeViewfinder = "qrcode.viewfinder"
    case rectangleStack = "rectangle.stack"
    case rectangleStackFill = "rectangle.stack.fill"
    case trayFullFill = "tray.full.fill"
    case sparklesRectangleStackFill = "sparkles.rectangle.stack.fill"
    case serverRack = "server.rack"
    case shieldFill = "shield.fill"
    case shieldLefthalfFilled = "shield.lefthalf.filled"
    case shippingbox = "shippingbox"
    case sliderHorizontal3 = "slider.horizontal.3"
    case speedometer = "speedometer"
    case squareAndArrowDown = "square.and.arrow.down"
    case squareAndArrowUp = "square.and.arrow.up"
    case squareGrid2x2 = "square.grid.2x2"
    case stopFill = "stop.fill"
    case textAlignleft = "text.alignleft"
    case trash = "trash"
    case waveformPathEcg = "waveform.path.ecg"
    case wifi = "wifi"
    case wrenchAndScrewdriver = "wrench.and.screwdriver"
    case wrenchAndScrewdriverFill = "wrench.and.screwdriver.fill"
     
     
     
    case githubMark = "github.mark"
     
     
    case xLogo = "x.logo"
    case xmark = "xmark"
    case xmarkCircle = "xmark.circle"
    case xmarkCircleFill = "xmark.circle.fill"
    case xmarkOctagonFill = "xmark.octagon.fill"

    public var isCustom: Bool {
        self == .catCircleFill || self == .ruleDomain
            || self == .dnsDomain || self == .githubMark || self == .xLogo
    }

     
     
     
     
     
     
    public func customImage(bundle: Bundle? = nil) -> Image {
        Image(decorative: rawValue, bundle: bundle)
    }

     
     
     
     
     
    public var opticalScale: Double {
        switch self {
        case .catCircleFill, .ruleDomain, .dnsDomain:
            1.25
        default:
            1
        }
    }

     
     
     
     
     
     
    nonisolated(unsafe) public static var platformName: (ClashSymbol) -> String = \.rawValue

    public var drawableName: String { Self.platformName(self) }

    public var candidates: [String] {
        switch self {
        case .profileClipboard:
            [rawValue, "list.bullet.rectangle"]
        case .proxyDomain:
            [rawValue, "slider.horizontal.below.square.filled.and.square"]
         
         
         
         
        case .arrowUpDocument:
            [rawValue, "doc.badge.arrow.up", "square.and.arrow.down"]
        case .pencilLine:
            [rawValue, "pencil"]
        case .arrowDownLeftAndArrowUpRight:
            [rawValue, "arrow.up.left.and.arrow.down.right"]
        case .arrowUpRightAndArrowDownLeft:
            [rawValue, "arrow.down.right.and.arrow.up.left"]
        case .gaugeWithDotsNeedle33Percent:
            [rawValue, "speedometer"]
        case .networkSlash:
            [rawValue, "wifi.slash"]
        default:
            [rawValue]
        }
    }
}
