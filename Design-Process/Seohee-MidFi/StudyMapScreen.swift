//
//  StudyMapScreen.swift
//  Design layer – 지도 화면 (팀원의 StudySpotsView 를 디자인만 새로 입힌 버전)
//
//  ✅ 팀원 코드(SpotStore, MapSearchModel, AuthStore, CommunitySpot, DirectionsSheet 등)는
//     수정하지 않고 그대로 가져다 써요. 데이터 읽기/쓰기 로직 호출은 원본과 동일해요.
//  ✅ 원래 StudySpotsView 는 파일에 그대로 남아 있어서 언제든 되돌릴 수 있어요.
//

import SwiftUI
import MapKit
import Charts
import FirebaseAuth

// MARK: - Map screen

struct StudyMapScreen: View {
    @EnvironmentObject private var auth: AuthStore

    @StateObject private var store = SpotStore()
    @StateObject private var search = MapSearchModel()

    @State private var mode: SpotListMode = .community
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437),
            span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
        )
    )
    @State private var selectedSpot: CommunitySpot?
    @State private var isBlinking = false
    @State private var cardOffset: CGFloat = 260
    @State private var showDirections = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    PillSegmented(
                        options: [
                            PillOption(SpotListMode.community, "Community"),
                            PillOption(SpotListMode.mySaved, "My saved")
                        ],
                        selection: $mode,
                        height: 68
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                    mapView
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Theme.mist, lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
                .background(Color.white)

                if let selectedSpot {
                    StyledSpotSheet(
                        spot: selectedSpot,
                        store: store,
                        userID: auth.user?.uid ?? "",
                        cardOffset: $cardOffset,
                        onDirections: { showDirections = true },
                        onClose: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                self.selectedSpot = nil
                            }
                        }
                    )
                    .id(selectedSpot.id)
                    .frame(height: min(geometry.size.height * 0.72, 680))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if isBlinking {
                    Color.white
                        .opacity(0.88)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
        }
        .task {
            guard let uid = auth.user?.uid else { return }
            store.listen(mode: mode, userID: uid)
            store.listenForSavedSpotIDs(userID: uid)
        }
        .onDisappear {
            store.stopListening()
        }
        .onChange(of: mode) { _, newValue in
            selectedSpot = nil
            store.selectedSpotID = nil
            cardOffset = 260
            guard let uid = auth.user?.uid else { return }
            blinkAndReload(newValue, userID: uid)
        }
        .onChange(of: store.selectedSpotID) { _, newID in
            guard let newID else { return }
            store.fetchSpot(newID) { spot in
                guard let spot else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    selectedSpot = spot
                    cardOffset = 260
                }
                focusMap(on: spot.coordinate)
            }
        }
        .sheet(isPresented: $showDirections) {
            if let selectedSpot {
                DirectionsSheet(spot: selectedSpot)
            }
        }
        .alert("Map / Cloud Error", isPresented: .constant(!store.errorMessage.isEmpty || !search.errorMessage.isEmpty)) {
            Button("OK") {
                store.errorMessage = ""
                search.errorMessage = ""
            }
        } message: {
            Text(store.errorMessage.isEmpty ? search.errorMessage : store.errorMessage)
        }
    }

    // MARK: Header (title + search)

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Study Spots")
                .font(Theme.heading(36))
                .foregroundStyle(Theme.navy)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.navy.opacity(0.6))

                TextField("Search campus, library, cafe", text: $search.query)
                    .font(Theme.body(18))
                    .foregroundStyle(Theme.navy)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .onSubmit { search.search() }

                if search.isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 62)
            .themedCard(Theme.mist, radius: 28)

            if !search.results.isEmpty {
                StyledSearchResults(
                    results: search.results,
                    onSelect: { result in
                        guard let uid = auth.user?.uid else { return }
                        search.results = []
                        search.query = result.name

                        // 원본과 동일: 검색 결과는 먼저 Community Spots 에 추가돼요. (My Saved 에는 자동 추가 X)
                        store.addCommunitySpot(result, userID: uid) { spot in
                            guard let spot else { return }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                selectedSpot = spot
                                cardOffset = 260
                            }
                            focusMap(on: spot.coordinate)
                        }
                    }
                )
            }
        }
    }

    // MARK: Map

    private var mapView: some View {
        Map(position: $cameraPosition) {
            ForEach(Array(store.spots.enumerated()), id: \.element.id) { index, spot in
                Annotation("", coordinate: spot.coordinate) {
                    StyledPin(
                        number: mode == .mySaved ? index + 1 : nil,
                        isSelected: selectedSpot?.id == spot.id
                    ) {
                        store.selectedSpotID = spot.id
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .overlay(alignment: .bottomTrailing) {
            if store.isLoading {
                ProgressView()
                    .padding(12)
                    .background(.thinMaterial)
                    .clipShape(Circle())
                    .padding(12)
            }
        }
    }

    private func focusMap(on coordinate: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 0.45)) {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
                )
            )
        }
    }

    private func blinkAndReload(_ newMode: SpotListMode, userID: String) {
        withAnimation(.easeIn(duration: 0.08)) {
            isBlinking = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            store.listen(mode: newMode, userID: userID)
            withAnimation(.easeOut(duration: 0.18)) {
                isBlinking = false
            }
        }
    }
}

// MARK: - Search results

private struct StyledSearchResults: View {
    let results: [SearchResult]
    let onSelect: (SearchResult) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(results) { result in
                Button {
                    onSelect(result)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.sage)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.name)
                                .font(Theme.body(15, .semibold))
                                .foregroundStyle(Theme.navy)
                                .lineLimit(1)

                            Text(result.address)
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.sage)
                                .lineLimit(2)
                        }

                        Spacer()

                        Text("Add")
                            .font(Theme.body(13, .bold))
                            .foregroundStyle(Theme.navy)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if result.id != results.last?.id {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(Theme.cream, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 14, y: 8)
    }
}

// MARK: - Pin

private struct StyledPin: View {
    let number: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let number {
                    ZStack {
                        Circle().fill(isSelected ? Theme.navy : Theme.sage)
                        Text("\(number)")
                            .font(Theme.body(15, .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 38, height: 38)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                } else {
                    Image(systemName: "mappin.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? Theme.navy : Theme.sage)
                        .font(.system(size: 40))
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
            .scaleEffect(isSelected ? 1.28 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bottom sheet

private struct OccupancyPoint: Identifiable {
    let id = UUID()
    let hour: Double
    let value: Double

    // 디자인 확인용 샘플 곡선 (DesignFlags.showSampleCrowdData == true 일 때만 사용)
    static let sample: [OccupancyPoint] = [
        (9, 0.03), (12, 0.20), (15, 0.40), (18, 0.60), (19.5, 0.70), (21, 0.50)
    ].map { OccupancyPoint(hour: $0.0, value: $0.1) }
}

struct StyledSpotSheet: View {
    let spot: CommunitySpot
    @ObservedObject var store: SpotStore
    let userID: String
    @Binding var cardOffset: CGFloat
    let onDirections: () -> Void
    let onClose: () -> Void

    @EnvironmentObject private var design: DesignState

    @State private var seats = ""
    @State private var outlets = ""
    @State private var food: FoodChoice = .yes
    @State private var volume = 3
    @State private var accessible = true
    @State private var access: AccessRestriction = .publicAccess
    @State private var savedContributionLoaded = false
    @State private var liveSpot: CommunitySpot

    init(
        spot: CommunitySpot,
        store: SpotStore,
        userID: String,
        cardOffset: Binding<CGFloat>,
        onDirections: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.spot = spot
        self.store = store
        self.userID = userID
        self._cardOffset = cardOffset
        self.onDirections = onDirections
        self.onClose = onClose
        self._liveSpot = State(initialValue: spot)
    }

    var body: some View {
        let displaySpot = liveSpot

        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.cream)
                .frame(width: 46, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(dragGesture)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    titleRow(displaySpot)

                    AssetImage(name: "spot_photo_placeholder", symbol: "cup.and.saucer.fill", fill: true)
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                        .background(Theme.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button(action: onDirections) {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                    .buttonStyle(SagePrimaryButtonStyle())

                    statusCard

                    if DesignFlags.showSampleCrowdData {
                        occupancyCard
                    }

                    communityInfoCard(displaySpot)

                    updateFormCard(displaySpot)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { dismissKeyboard() }
        }
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 40,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 40,
                style: .continuous
            )
            .fill(Theme.mist)
        )
        .shadow(color: .black.opacity(0.14), radius: 22, y: -6)
        .offset(y: cardOffset)
        .onAppear { loadCurrentData() }
        .onChange(of: spot.id) { _, _ in
            savedContributionLoaded = false
            loadCurrentData()
        }
        .onChange(of: store.spots) { _, updatedSpots in
            if let refreshed = updatedSpots.first(where: { $0.id == liveSpot.id }) {
                liveSpot = refreshed
            }
        }
    }

    // MARK: Title row

    private func titleRow(_ displaySpot: CommunitySpot) -> some View {
        let isSaved = store.savedSpotIDs.contains(displaySpot.id)

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(displaySpot.name)
                    .font(Theme.heading(30))
                    .foregroundStyle(Theme.navy)
                    .lineLimit(2)

                if DesignFlags.showSampleCrowdData {
                    HStack(spacing: 8) {
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { index in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(index < 3 ? Theme.butter : Theme.cream)
                            }
                        }
                        Text("(361)")
                            .font(Theme.body(14, .semibold))
                            .foregroundStyle(Theme.navy)
                    }
                }

                Text(displaySpot.hoursText)
                    .font(Theme.body(14))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(displaySpot.address)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.navy.opacity(0.7))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            // 북마크 = 원본의 "Save to My Saved" 버튼과 같은 동작
            Button {
                if !isSaved {
                    store.saveToMySaved(spot: displaySpot, userID: userID) { _ in }
                }
            } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.navy)
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.navy.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Current status card

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current Status")
                .font(Theme.body(16, .semibold))
                .foregroundStyle(Theme.sage)

            if DesignFlags.showSampleCrowdData {
                HStack(spacing: 14) {
                    Circle().fill(Theme.navy).frame(width: 30, height: 30)
                    Text("Moderate")
                        .font(Theme.body(34, .bold))
                        .foregroundStyle(Theme.navy)
                }

                HStack {
                    Text("About 60% full")
                        .font(Theme.body(17))
                        .foregroundStyle(Theme.navy)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Getting busier")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(Theme.body(15, .semibold))
                    .foregroundStyle(Theme.sage)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.mist)
                        Capsule().fill(Theme.navy).frame(width: geo.size.width * 0.6)
                    }
                }
                .frame(height: 12)

                Text("Updated 8 min ago")
                    .font(Theme.body(15, .semibold))
                    .foregroundStyle(Theme.sage)
            } else {
                Text("No live crowd reports yet")
                    .font(Theme.body(20, .bold))
                    .foregroundStyle(Theme.navy)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(Theme.butter, radius: 32)
    }

    // MARK: Occupancy chart (sample)

    private var occupancyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Population Growth")
                        .font(Theme.body(20, .bold))
                        .foregroundStyle(Theme.sage)
                    Text("Estimated occupancy throughout the day")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.navy)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Theme.navy).frame(width: 12, height: 12)
                    Text("60%")
                        .font(Theme.body(16, .bold))
                        .foregroundStyle(Theme.navy)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white, in: Capsule())
            }

            Chart {
                ForEach(OccupancyPoint.sample) { point in
                    AreaMark(
                        x: .value("Hour", point.hour),
                        y: .value("Occupancy", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.sage.opacity(0.2))

                    LineMark(
                        x: .value("Hour", point.hour),
                        y: .value("Occupancy", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.navy)
                    .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round))
                }

                RuleMark(x: .value("Now", 18))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    .foregroundStyle(Theme.sage)
                    .annotation(position: .top, spacing: 2) {
                        Text("Now")
                            .font(Theme.body(14, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(Theme.navy, in: Capsule())
                    }

                PointMark(x: .value("Now", 18), y: .value("Occupancy", 0.6))
                    .symbolSize(110)
                    .foregroundStyle(Theme.navy)
            }
            .chartYScale(domain: 0...1)
            .chartXScale(domain: 9...21)
            .chartXAxis {
                AxisMarks(values: [9, 12, 15, 18, 21]) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text(Self.hourLabel(hour))
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.sage)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 0.5, 1.0]) { value in
                    AxisGridLine().foregroundStyle(Theme.sage.opacity(0.3))
                    AxisValueLabel {
                        if let ratio = value.as(Double.self) {
                            Text("\(Int(ratio * 100))%")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.sage)
                        }
                    }
                }
            }
            .frame(height: 190)
            .padding(.top, 14)
        }
        .padding(20)
        .themedCard(Theme.butterLight, radius: 32)
    }

    private static func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 9: return "9 AM"
        case 12: return "12 PM"
        case 15: return "3 PM"
        case 18: return "6 PM"
        case 21: return "9 PM"
        default: return "\(hour)"
        }
    }

    // MARK: Community info (진짜 Firestore 데이터)

    private func communityInfoCard(_ displaySpot: CommunitySpot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Community updates")
                .font(Theme.heading(24))
                .foregroundStyle(Theme.navy)

            Text("Current consensus from \(displaySpot.contributionCount) update(s)")
                .font(Theme.body(12))
                .foregroundStyle(Theme.sage)

            infoRow("Seats (estimate)", displaySpot.averageSeats.map(String.init) ?? "—")
            infoRow("Outlets", displaySpot.averageOutlets.map(String.init) ?? "—")
            infoRow("Food allowed", displaySpot.communityFood?.rawValue ?? "No updates yet")
            infoRow("Volume level", displaySpot.averageVolume.map { "\($0)/5" } ?? "No updates yet")
            infoRow("Accessibility", displaySpot.communityAccessibility.map { $0 ? "Yes" : "No" } ?? "No updates yet")
            infoRow("Access restrictions", displaySpot.communityAccessRestriction?.rawValue ?? "No updates yet")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(Theme.cream, radius: 32)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.body(14))
                .foregroundStyle(Theme.sage)
            Spacer()
            Text(value)
                .font(Theme.body(14, .bold))
                .foregroundStyle(Theme.navy)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: Update form (원본과 동일한 입력 항목 / 저장 로직)

    private func updateFormCard(_ displaySpot: CommunitySpot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add your update")
                .font(Theme.heading(24))
                .foregroundStyle(Theme.navy)

            HStack(spacing: 12) {
                numberField("Seats", text: $seats)
                numberField("Outlets", text: $outlets)
            }

            formSection("Food allowed") {
                ThemedChoiceGrid(values: FoodChoice.allCases, selected: food) { food = $0 }
            }

            formSection("Volume level") {
                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            volume = value
                        } label: {
                            Circle()
                                .fill(value <= volume ? Theme.butter : Color.white)
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Text("\(value)")
                                        .font(Theme.body(14, .bold))
                                        .foregroundStyle(value <= volume ? Theme.navy : Theme.sage)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            formSection("Accessibility") {
                HStack(spacing: 8) {
                    yesNoButton("Yes", selected: accessible) { accessible = true }
                    yesNoButton("No", selected: !accessible) { accessible = false }
                }
            }

            formSection("Access restrictions") {
                ThemedChoiceGrid(values: AccessRestriction.allCases, selected: access) { access = $0 }
            }

            Button {
                dismissKeyboard()
                guard !userID.isEmpty else { return }

                let contribution = CommunityContribution(
                    seats: Int(seats),
                    outlets: Int(outlets),
                    food: food,
                    volume: volume,
                    accessible: accessible,
                    accessRestriction: access
                )

                store.saveContribution(
                    spot: displaySpot,
                    contribution: contribution,
                    userID: userID,
                    completion: {
                        store.fetchSpot(displaySpot.id) { refreshed in
                            if let refreshed {
                                liveSpot = refreshed
                            }
                        }
                        // 공유할 때마다 포인트 지급 (지금은 화면용 로컬 값. 저장은 팀원과 연결 필요)
                        design.awardPoints(10)
                    }
                )
            } label: {
                Text("Submit update  (+10 pt)")
            }
            .buttonStyle(SagePrimaryButtonStyle())

            Text("Everyone shares Community Spots. My Saved is private to the signed-in account.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.sage)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(Theme.cream, radius: 32)
    }

    private func numberField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.sage)

            TextField("Estimate", text: text)
                .keyboardType(.numberPad)
                .font(Theme.body(17))
                .foregroundStyle(Theme.navy)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(Theme.body(14, .bold))
                .foregroundStyle(Theme.navy)
            content()
        }
    }

    private func yesNoButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(15, .bold))
                .foregroundStyle(selected ? Theme.navy : Theme.sage)
                .frame(width: 80, height: 44)
                .background(selected ? Theme.butter : Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Data loading + drag (원본과 동일)

    private func loadCurrentData() {
        if !userID.isEmpty {
            store.fetchSpot(liveSpot.id) { refreshed in
                if let refreshed {
                    liveSpot = refreshed
                }
            }
        }

        guard !savedContributionLoaded, !userID.isEmpty else { return }
        savedContributionLoaded = true

        store.fetchMyContribution(spotID: liveSpot.id, userID: userID) { contribution in
            guard let contribution else { return }
            seats = contribution.seats.map(String.init) ?? ""
            outlets = contribution.outlets.map(String.init) ?? ""
            food = contribution.food
            volume = contribution.volume
            accessible = contribution.accessible
            access = contribution.accessRestriction
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let proposed = 260 + value.translation.height
                cardOffset = min(310, max(0, proposed))
            }
            .onEnded { value in
                let shouldExpand = value.translation.height < -65 || cardOffset < 130
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    cardOffset = shouldExpand ? 0 : 260
                }
            }
    }
}

// MARK: - Themed choice grid

private struct ThemedChoiceGrid<Value: Hashable & Identifiable & RawRepresentable>: View where Value.RawValue == String {
    let values: [Value]
    let selected: Value
    let action: (Value) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
            ForEach(values) { value in
                let isSelected = selected == value

                Button {
                    action(value)
                } label: {
                    Text(value.rawValue)
                        .font(Theme.body(14, .semibold))
                        .foregroundStyle(isSelected ? Theme.navy : Theme.sage)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isSelected ? Theme.butter : Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
