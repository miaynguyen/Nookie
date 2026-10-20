//
//  Theme.swift
//  Design layer (Figma → SwiftUI)
//
//  색상 / 폰트 / 공통 스타일은 전부 여기서만 바꾸면 앱 전체에 반영돼요.
//

import SwiftUI
import CoreText

// MARK: - Design tokens

enum Theme {
    // Colors (Figma에서 뽑은 값)
    static let sage        = Color(hex: 0x9BA487)   // 메인 버튼, 보조 텍스트
    static let cream       = Color(hex: 0xF5F3E8)   // 카드 / 탭바 배경
    static let butter      = Color(hex: 0xF4E9BB)   // 선택된 탭, 상태 카드
    static let butterLight = Color(hex: 0xFDF1C8)   // 차트 카드
    static let mist        = Color(hex: 0xC4D2D9)   // 입력창, 메뉴 버튼
    static let navy        = Color(hex: 0x132F43)   // 제목 / 강조 텍스트
    static let roomBG      = Color(hex: 0xFCF6EA)   // 스터디룸 카드 배경

    // Fonts
    // 폰트 파일(Fonts 폴더)을 프로젝트에 추가만 하면 코드에서 자동 등록돼요. (Info.plist 수정 불필요)
    // 파일이 없으면 시스템 폰트로 대체되니까 앱이 깨지지는 않아요.
    private static let fontsRegistered: Bool = {
        let bundle = Bundle.main
        var urls = bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        urls += bundle.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        urls += bundle.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return true
    }()

    /// 제목용 필기체 (Lobster Two Bold Italic)
    static func heading(_ size: CGFloat) -> Font {
        _ = fontsRegistered
        return .custom("LobsterTwo-BoldItalic", size: size)
    }

    /// 본문용 (Open Sans)
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        _ = fontsRegistered
        return Font.custom("Open Sans", size: size).weight(weight)
    }
}

/// 팀원 데이터 모델에 아직 없는 값(혼잡도 %, 별점 등)을 디자인 확인용 샘플로 보여줄지 여부.
/// 발표/데모 땐 true, 실제 데이터가 연결되면 false로 바꾸세요.
enum DesignFlags {
    static let showSampleCrowdData = true
}

// MARK: - Color helper

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - View helpers

extension View {
    func themedCard(_ color: Color, radius: CGFloat = 28) -> some View {
        background(color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
