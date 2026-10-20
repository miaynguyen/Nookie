import SwiftUI
import FirebaseAuth

struct CharacterStyle: Equatable {
    var model = 0 // Legacy saved value: 1 means a former boy style numbered 1–5.
    var hair = 7
    var top = 1
    var bottom = 1
    var shoes = 1
}

/// Artwork uses one coordinate system. All positions below are relative to the
/// 126 × 250 Model Template, with 20 points of clear space above the head.
struct CharacterArtwork: View {
    let width: CGFloat
    let style: CharacterStyle

    var body: some View {
        ZStack(alignment: .topLeading) {
            layer("character_model", width: 126, height: 250, x: 0, y: 20)
            if style.shoes > 0 {
                layer(String(format: "character_shoes_%02d", style.shoes), width: 98,
                      height: 100 * 82 / 165, x: 13, y: 219)
            }
            if style.bottom > 0 {
                layer(String(format: "character_bottom_%02d", style.bottom), width: 120,
                      height: style.bottom == 1 ? 132 : 129, x: 5, y: 120)
            }
            if style.top > 0 {
                layer(String(format: "character_top_%02d", style.top), width: 95,
                      height: 80, x: 15, y: 80)
            }
            if style.hair > 0 {
                let boyStyle = style.hair > 5 || (style.model == 1 && style.hair <= 5)
                let imageNumber = style.hair > 5 ? style.hair - 5 : style.hair
                layer(String(format: "character_hair_%@_%02d", boyStyle ? "boy" : "girl", imageNumber),
                      width: 120, height: !boyStyle && imageNumber <= 2 ? 127 : 124,
                      x: boyStyle ? -1 : 3,
                      y: boyStyle ? 0 : 2)
            }
        }
        .frame(width: 126, height: 275, alignment: .topLeading)
        .scaleEffect(width / 126, anchor: .topLeading)
        .frame(width: width, height: width * 275 / 126, alignment: .topLeading)
        .accessibilityLabel("Customized study companion")
    }

    private func layer(_ name: String, width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .frame(width: width, height: height)
            .offset(x: x, y: y)
    }
}

/// Saved appearance used on Home and Profile. The editor maintains its own draft.
struct SavedCharacterArtwork: View {
    @AppStorage("character.v2.model") private var model = 0
    @AppStorage("character.v2.hair") private var hair = 7
    @AppStorage("character.v2.top") private var top = 1
    @AppStorage("character.v2.bottom") private var bottom = 1
    @AppStorage("character.v2.shoes") private var shoes = 1

    let width: CGFloat

    var body: some View {
        CharacterArtwork(width: width, style: CharacterStyle(model: model, hair: hair, top: top, bottom: bottom, shoes: shoes))
    }
}

private enum CharacterCategory: String, CaseIterable {
    case hair = "Hair"
    case tops = "Tops"
    case bottoms = "Bottoms"
    case shoes = "Shoes"

    var count: Int {
        switch self {
        case .hair: return 10
        case .tops: return 9
        case .bottoms, .shoes: return 10
        }
    }
}

private enum EditorMode: Hashable {
    case character, room
}

struct CharacterStudioView: View {
    @EnvironmentObject private var design: DesignState
    let onboarding: Bool
    let onComplete: (() -> Void)?

    init(onboarding: Bool = false, onComplete: (() -> Void)? = nil) {
        self.onboarding = onboarding
        self.onComplete = onComplete
    }
    @AppStorage("character.v2.model") private var savedModel = 0
    @AppStorage("character.v2.hair") private var savedHair = 7
    @AppStorage("character.v2.top") private var savedTop = 1
    @AppStorage("character.v2.bottom") private var savedBottom = 1
    @AppStorage("character.v2.shoes") private var savedShoes = 1
    @AppStorage("room.choice") private var room = 0

    @State private var draft = CharacterStyle()
    @State private var mode: EditorMode = .character
    @State private var category: CharacterCategory = .hair
    @State private var saveStatus = ""
    @State private var pendingUnlock: Int?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !onboarding {
                PillSegmented(
                    options: [PillOption(EditorMode.character, "Character"),
                              PillOption(EditorMode.room, "Room")],
                    selection: $mode,
                    height: 58
                )
            }

            if mode == .character {
                CharacterArtwork(width: 160, style: draft)
                    .frame(maxWidth: .infinity, minHeight: 380)
                    .background(Theme.cream, in: RoundedRectangle(cornerRadius: 32))

                categoryPicker
                itemGrid

                Button(onboarding ? "Save & Continue" : (saveStatus.isEmpty ? "Save Character" : "Saved ✓")) { saveCharacter() }
                    .buttonStyle(SagePrimaryButtonStyle())
                    .disabled(onboarding && !isComplete)
                    .opacity(onboarding && !isComplete ? 0.5 : 1)
                    .padding(.top, 6)

                if onboarding && !isComplete {
                    Text("Choose a hairstyle, top, bottom, and shoes to continue.")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.sage)
                        .frame(maxWidth: .infinity)
                }

                if !saveStatus.isEmpty {
                    Text(saveStatus)
                        .font(Theme.body(15, .semibold))
                        .foregroundStyle(Theme.sage)
                        .frame(maxWidth: .infinity)
                }
            } else {
                StudyRoomScene()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(900.0 / 950.0, contentMode: .fit)
                    .padding(12)
                    .background(Theme.cream, in: RoundedRectangle(cornerRadius: 32))

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(RoomChoice.displayOrder, id: \.rawValue) { choice in
                        roomButton(choice)
                    }
                }
                Button(saveStatus == "Room saved" ? "Saved ✓" : "Save Room") {
                    saveStatus = "Room saved"
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                .buttonStyle(SagePrimaryButtonStyle())
                .padding(.top, 10)
                .padding(.bottom, 190)
            }
        }
        .onAppear {
            let unifiedHair = savedModel == 1 && (1...5).contains(savedHair) ? savedHair + 5 : savedHair
            draft = onboarding
                ? CharacterStyle(model: 0, hair: 7, top: 0, bottom: 0, shoes: 0)
                : CharacterStyle(model: 0, hair: unifiedHair, top: savedTop,
                                 bottom: savedBottom, shoes: savedShoes)
        }
        .alert("Unlock this item?", isPresented: Binding(
            get: { pendingUnlock != nil },
            set: { if !$0 { pendingUnlock = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingUnlock = nil }
            Button("Unlock for \(price(for: pendingUnlock ?? 1)) pt") {
                guard let number = pendingUnlock else { return }
                if design.unlock(itemID(number), cost: price(for: number)) {
                    select(number)
                    saveStatus = "Unlocked! \(design.points) pt remaining"
                } else {
                    saveStatus = "Not enough points yet"
                }
                pendingUnlock = nil
            }
        } message: {
            Text("Your balance: \(design.points) pt. Earn points with a focus session or a new spot update.")
        }
    }

    private var categoryPicker: some View {
        HStack(spacing: 2) {
            ForEach(CharacterCategory.allCases, id: \.self) { item in
                Button {
                    withAnimation(.snappy) { category = item }
                } label: {
                    Text(item.rawValue)
                        .font(Theme.body(15, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(category == item ? Theme.navy : Theme.sage)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(category == item ? Theme.butter : .clear,
                                    in: RoundedRectangle(cornerRadius: 22))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Theme.cream, in: RoundedRectangle(cornerRadius: 27))
    }

    private var itemGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(1...category.count, id: \.self) { number in
                Button {
                    if isFree(number) || design.owns(itemID(number)) {
                        select(number)
                        saveStatus = ""
                    } else {
                        pendingUnlock = number
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(assetName(for: number))
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 74)
                        Text(isFree(number) ? "Free" : design.owns(itemID(number)) ? "Owned" : "🔒 \(price(for: number)) pt")
                            .font(Theme.body(12, .semibold))
                            .foregroundStyle(Theme.navy)
                    }
                        .padding(6)
                        .frame(maxWidth: .infinity, minHeight: 105)
                        .background(Theme.mist.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18)
                            .stroke(selectedNumber == number ? Theme.navy : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(category.rawValue) style \(number), \(isFree(number) ? "free" : design.owns(itemID(number)) ? "owned" : "locked for \(price(for: number)) points")")
                .accessibilityAddTraits(selectedNumber == number ? .isSelected : [])
            }
        }
    }

    private func roomButton(_ choice: RoomChoice) -> some View {
        Button { room = choice.rawValue } label: {
            VStack(spacing: 6) {
                Image(choice.assetName).resizable().scaledToFit().frame(height: 120)
                Text(choice.title).font(Theme.body(16, .semibold))
            }
            .foregroundStyle(Theme.navy)
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(Theme.cream, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22)
                .stroke(room == choice.rawValue ? Theme.navy : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(choice.title) study room")
        .accessibilityAddTraits(room == choice.rawValue ? .isSelected : [])
    }

    private var selectedNumber: Int {
        switch category {
        case .hair: return draft.hair
        case .tops: return draft.top
        case .bottoms: return draft.bottom
        case .shoes: return draft.shoes
        }
    }

    private var isComplete: Bool {
        draft.hair > 0 && draft.top > 0 && draft.bottom > 0 && draft.shoes > 0
    }

    private func itemID(_ number: Int) -> String { "\(category.rawValue).\(number)" }

    private func isFree(_ number: Int) -> Bool {
        number <= 2 || (category == .hair && (number == 6 || number == 7))
    }

    private func price(for number: Int) -> Int {
        switch category {
        case .hair:
            let groupNumber = number > 5 ? number - 5 : number
            return 30 + (groupNumber - 3) * 10
        case .tops: return 40 + (number - 3) * 10
        case .bottoms: return 45 + (number - 3) * 10
        case .shoes: return 35 + (number - 3) * 10
        }
    }

    private func assetName(for number: Int) -> String {
        switch category {
        case .hair: return String(format: "character_hair_%@_%02d", number > 5 ? "boy" : "girl", number > 5 ? number - 5 : number)
        case .tops: return String(format: "character_top_%02d", number)
        case .bottoms: return String(format: "character_bottom_%02d", number)
        case .shoes: return String(format: "character_shoes_%02d", number)
        }
    }

    private func select(_ number: Int) {
        switch category {
        case .hair:
            draft.hair = number
            draft.model = 0
        case .tops: draft.top = number
        case .bottoms: draft.bottom = number
        case .shoes: draft.shoes = number
        }
    }

    private func saveCharacter() {
        savedModel = 0
        savedHair = draft.hair
        savedTop = draft.top
        savedBottom = draft.bottom
        savedShoes = draft.shoes
        saveStatus = "Character saved"
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onComplete?()
    }

}

enum RoomChoice: Int {
    // Values 0 and 1 preserve previously saved blue/pink preferences.
    case sky = 0, blush = 1, vintage = 2, gaming = 3

    static let displayOrder: [RoomChoice] = [.gaming, .vintage, .sky, .blush]

    var title: String {
        switch self {
        case .sky: return "Sky Blue"
        case .blush: return "Blush Pink"
        case .vintage: return "Vintage"
        case .gaming: return "Gaming"
        }
    }

    var assetName: String {
        switch self {
        case .sky: return "room_sky"
        case .blush: return "room_blush"
        case .vintage: return "room_vintage"
        case .gaming: return "room_gaming"
        }
    }

    var characterX: CGFloat {
        switch self {
        case .gaming: return 0.54
        case .vintage: return 0.56
        case .sky: return 0.52
        case .blush: return 0.56
        }
    }
}

struct RoomArtwork: View {
    @AppStorage("room.choice") private var room = 0

    var body: some View {
        let choice = RoomChoice(rawValue: room) ?? .sky
        Image(choice.assetName)
            .resizable()
            .scaledToFit()
            .accessibilityLabel("\(choice.title) study room")
    }
}

/// The character stays independent from the room image, so changing outfits or
/// backgrounds never requires exporting another composite image.
struct StudyRoomScene: View {
    @AppStorage("room.choice") private var room = 0

    var body: some View {
        let choice = RoomChoice(rawValue: room) ?? .sky
        GeometryReader { geometry in
            ZStack {
                RoomArtwork()
                    .frame(width: geometry.size.width, height: geometry.size.height)

                Ellipse()
                    .fill(Theme.navy.opacity(0.10))
                    .frame(width: geometry.size.width * 0.11,
                           height: geometry.size.height * 0.018)
                    .position(x: geometry.size.width * choice.characterX,
                              y: geometry.size.height * 0.844)

                SavedCharacterArtwork(width: geometry.size.width * 0.19)
                    .position(x: geometry.size.width * 0.58,
                              y: geometry.size.height * 0.45)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(900.0 / 950.0, contentMode: .fit)
        .accessibilityElement(children: .combine)
    }
}

/// Shown only after creating a new account. The draft starts with the bare model.
struct FirstCharacterSetupView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var design = DesignState()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Make your study companion")
                    .font(Theme.heading(32))
                    .foregroundStyle(Theme.navy)
                Text("Start with a blank character. Choose free basics or unlock more with points.")
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.sage)
                Text("\(design.points) pt")
                    .font(Theme.heading(24))
                    .foregroundStyle(Theme.navy)
                CharacterStudioView(onboarding: true) { auth.finishCharacterSetup() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 50)
        }
        .background(Color.white.ignoresSafeArea())
        .environmentObject(design)
        .onAppear { design.configure(userID: auth.user?.uid ?? "") }
    }
}
