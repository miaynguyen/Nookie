//
//  StudyMapScreen.swift
//  Styled map with community reports, wishlist, and a draggable detail card.
//

import SwiftUI
import MapKit
import FirebaseAuth
import FirebaseFirestore
import PhotosUI
import UIKit

// MARK: - Map screen

struct StudyMapScreen: View {
    init(initialMode: SpotListMode = .community) {
        _mode = State(initialValue: initialMode)
    }
    @EnvironmentObject private var auth: AuthStore

    @StateObject private var store = SpotStore()
    @StateObject private var search = MapSearchModel()
    @ObservedObject private var location = LocationPermission.shared

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
    @State private var ignoreMapTap = false

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
                            PillOption(SpotListMode.wantToGo, "Want To Go"),
                            PillOption(SpotListMode.mySaved, "Favorites")
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
                        .padding(.bottom, 22)
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
                                store.selectedSpotID = nil
                                cardOffset = 260
                            }
                        }
                    )
                    .id(selectedSpot.id)
                    .frame(height: min(geometry.size.height * 0.83, 760))
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
        .onAppear {
            location.refresh()
            if let coordinate = location.coordinate { focusMap(on: coordinate) }
        }
        .onChange(of: location.coordinate?.latitude) { _, _ in
            if let coordinate = location.coordinate { focusMap(on: coordinate) }
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
                guard let spot, store.selectedSpotID == newID else { return }
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
                        ignoreMapTap = true
                        store.selectedSpotID = spot.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            ignoreMapTap = false
                        }
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onTapGesture {
            guard !ignoreMapTap else { return }
            guard selectedSpot != nil else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                selectedSpot = nil
                store.selectedSpotID = nil
            }
        }
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
                            .font(.system(size: 19))
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
                        .font(.system(size: 39))
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

struct StyledSpotSheet: View {
    let spot: CommunitySpot
    @ObservedObject var store: SpotStore
    let userID: String
    @Binding var cardOffset: CGFloat
    let onDirections: () -> Void
    let onClose: () -> Void

    @EnvironmentObject private var design: DesignState

    @State private var busyChoice: Int?
    @State private var busyReports: [LiveBusyReport] = []
    @State private var busyReportsListener: ListenerRegistration?
    @State private var seats = ""
    @State private var outlets = ""
    @State private var food: FoodChoice? = nil
    @State private var volume: Int? = nil
    @State private var accessible: Bool? = nil
    @State private var access: AccessRestriction? = nil
    @State private var savedContributionLoaded = false
    @State private var liveSpot: CommunitySpot
    @State private var dragStart: CGFloat?
    @State private var chosenPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var showingUpdate = false
    @State private var rewardAmount = 0
    @State private var showingReward = false
    @State private var scrollSnapLocked = false

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
            VStack(spacing: 6) {
                Capsule().fill(Theme.cream).frame(width: 54, height: 6)
                EmptyView()
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(Rectangle())
            .gesture(dragGesture)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    titleRow(displaySpot)

                    photoGallery
                    statusCard(displaySpot)
                    HStack(spacing: 12) {
                        Button { store.toggleSpot(spot: displaySpot, userID: userID, wishlist: true) } label: {
                            Label("Want To Go", systemImage: "mappin")
                                .foregroundStyle(store.wantedSpotIDs.contains(displaySpot.id) ? Theme.navy : Theme.sage)
                        }.buttonStyle(CreamSecondaryButtonStyle())
                        Button { store.toggleSpot(spot: displaySpot, userID: userID, wishlist: false) } label: {
                            Label("Favorite", systemImage: "heart")
                                .foregroundStyle(store.savedSpotIDs.contains(displaySpot.id) ? Theme.navy : Theme.sage)
                        }.buttonStyle(CreamSecondaryButtonStyle())
                    }
                    Button(action: onDirections) {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                    .buttonStyle(SagePrimaryButtonStyle())

                    Button("Add your update · 3 coins per field") {
                        withAnimation { showingUpdate.toggle(); cardOffset = 0 }
                    }.buttonStyle(SagePrimaryButtonStyle())
                    if showingUpdate { updateFormCard(displaySpot) }
                    communityInfoCard(displaySpot)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: CommunitySectionPositionKey.self,
                                value: geometry.frame(in: .named("spotCardScroll")).minY)
                        })
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .coordinateSpace(name: "spotCardScroll")
            .onPreferenceChange(CommunitySectionPositionKey.self) { position in
                guard !showingUpdate, !scrollSnapLocked else { return }
                if cardOffset > 150 && position < 320 {
                    scrollSnapLocked = true
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) { cardOffset = 0 }
                } else if cardOffset < 50 && position > 490 {
                    scrollSnapLocked = true
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) { cardOffset = 260 }
                }
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
        .onAppear {
            loadCurrentData()
            startBusyReportsListener()
        }
        .onDisappear { busyReportsListener?.remove(); busyReportsListener = nil }
        .alert("You earned \(rewardAmount) coins! 🎉", isPresented: $showingReward) {
            Button("Nice!", role: .cancel) {}
        }
        .onChange(of: cardOffset) { _, _ in
            // Reset only when a fresh gesture begins; avoid scroll feedback loops.
        }
        .onChange(of: spot.id) { _, _ in
            scrollSnapLocked = false
            savedContributionLoaded = false
            loadCurrentData()
            startBusyReportsListener()
        }
        .onChange(of: store.spots) { _, updatedSpots in
            if let refreshed = updatedSpots.first(where: { $0.id == liveSpot.id }) {
                liveSpot = refreshed
            }
        }
    }

    // MARK: Title row

    private var photoGallery: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photos").font(Theme.heading(22)).foregroundStyle(Theme.navy)
            PhotosPicker(selection: $chosenPhoto, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.sage, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    if let photoData, let image = UIImage(data: photoData) {
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 95).clipped()
                    } else {
                        Label("Add a photo", systemImage: "plus.square.on.square")
                            .foregroundStyle(Theme.navy)
                    }
                }.frame(height: 95).clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .onChange(of: chosenPhoto) { _, newPhoto in
                Task { photoData = try? await newPhoto?.loadTransferable(type: Data.self) }
            }
            Text("Photo selected on this device. Cloud upload requires a hosting connection.")
                .font(Theme.body(11)).foregroundStyle(Theme.sage)
        }
    }

    private func titleRow(_ displaySpot: CommunitySpot) -> some View {
        let isSaved = store.savedSpotIDs.contains(displaySpot.id)

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(displaySpot.name)
                    .font(Theme.heading(30))
                    .foregroundStyle(Theme.navy)
                    .lineLimit(2)

                Text(displaySpot.address)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.navy.opacity(0.7))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 23))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.navy.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Live busyness: listen to community submissions in real time

    private func startBusyReportsListener() {
        busyReportsListener?.remove()
        busyReports = []
        busyReportsListener = Firestore.firestore()
            .collection("spots").document(spot.id)
            .collection("busyReports")
            .order(by: "createdAt", descending: true)
            .limit(to: 200)
            .addSnapshotListener { snapshot, error in
                if let error {
                    Task { @MainActor in store.errorMessage = error.localizedDescription }
                    return
                }
                let reports = (snapshot?.documents ?? []).compactMap { document -> LiveBusyReport? in
                    let data = document.data()
                    guard let value = data["value"] as? Int,
                          (1...5).contains(value),
                          let date = (data["createdAt"] as? Timestamp)?.dateValue() else { return nil }
                    return LiveBusyReport(value: value, date: date)
                }
                Task { @MainActor in busyReports = reports }
            }
    }

    private var busynessSummary: (rating: Int, count: Int, recent: Bool, date: Date)? {
        let cutoff = Date().addingTimeInterval(-2 * 60 * 60)
        let recent = busyReports.filter { $0.date >= cutoff }
        if !recent.isEmpty {
            let mean = Double(recent.reduce(0) { $0 + $1.value }) / Double(recent.count)
            return (Int(mean.rounded()), recent.count, true, recent.map(\.date).max() ?? Date())
        }
        guard let latest = busyReports.max(by: { $0.date < $1.date }) else { return nil }
        return (latest.value, 1, false, latest.date)
    }

    private func busynessLabel(_ value: Int) -> String {
        switch value {
        case 1: return "Empty"
        case 2: return "A few seats taken"
        case 3: return "Half full"
        case 4: return "Very busy"
        default: return "Full"
        }
    }

    // MARK: Current status card

    private func statusCard(_ displaySpot: CommunitySpot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current Status")
                .font(Theme.body(16, .semibold))
                .foregroundStyle(Theme.sage)

            Text("How busy is it?").font(Theme.body(18, .bold)).foregroundStyle(Theme.navy)
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { value in
                    Button("\(value)") { busyChoice = value }
                        .font(Theme.body(16, .bold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(busyChoice == value ? Theme.sage : Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(busyChoice == value ? .white : Theme.navy)
                }
            }
            HStack { Text("1 · Empty"); Spacer(); Text("5 · Full") }
                .font(Theme.body(12)).foregroundStyle(Theme.navy)
            Button("Submit · +5 coins") {
                guard let busyChoice, !userID.isEmpty else { return }
                store.submitBusyReport(spotID: displaySpot.id, userID: userID, value: busyChoice) {
                    design.awardPoints(5)
                    rewardAmount = 5
                    showingReward = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.busyChoice = nil
                }
            }
            .disabled(busyChoice == nil)
            .buttonStyle(SagePrimaryButtonStyle())
            if let summary = busynessSummary {
                Text("Community busyness: \(summary.rating)/5 · \(busynessLabel(summary.rating))")
                    .font(Theme.body(18, .bold))
                    .foregroundStyle(Theme.navy)
                Text(summary.recent
                     ? "Based on \(summary.count) report(s) in the last 2 hours"
                     : "No reports in the last 2 hours · latest report \(summary.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.sage)
            } else {
                Text("Community busyness: no reports yet")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.navy)
            }
            Text(displaySpot.averageAvailableSeats.map { "About \($0) open seats reported" } ?? "Open seats: no reports yet")
                .font(Theme.body(20, .bold))
                .foregroundStyle(Theme.navy)
            Text(displaySpot.averageOutlets.map { "About \($0) outlets reported" } ?? "Outlets: no reports yet")
                .font(Theme.body(16))
                .foregroundStyle(Theme.navy)
            if let volume = displaySpot.averageVolume {
                Text("Noise level: \(volume)/5")
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.navy)
            }
            Text("Based on \(displaySpot.contributionCount) community update(s) · estimates may change")
                .font(Theme.body(12))
                .foregroundStyle(Theme.sage)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(Theme.butter, radius: 32)
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

            infoRow("Open seats", displaySpot.averageAvailableSeats.map(String.init) ?? "No reports yet")
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
            HStack {
                Text("Add your update")
                    .font(Theme.heading(24))
                    .foregroundStyle(Theme.navy)
                Spacer()
                Text("3 coins per update")
                    .font(Theme.body(11, .semibold))
                    .foregroundStyle(Theme.sage)
            }

            HStack(spacing: 12) {
                numberField("Open seats now", text: $seats)
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
                                .fill((volume.map { value <= $0 } ?? false) ? Theme.butter : Color.white)
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Text("\(value)")
                                        .font(Theme.body(14, .bold))
                                        .foregroundStyle((volume.map { value <= $0 } ?? false) ? Theme.navy : Theme.sage)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            formSection("Accessibility") {
                HStack(spacing: 8) {
                    yesNoButton("Yes", selected: accessible == true) { accessible = true }
                    yesNoButton("No", selected: accessible == false) { accessible = false }
                }
            }

            formSection("Access restrictions") {
                ThemedChoiceGrid(values: AccessRestriction.allCases, selected: access) { access = $0 }
            }

            Button {
                dismissKeyboard()
                guard !userID.isEmpty else { return }

                let contribution = CommunityContribution(
                    seats: nil,
                    outlets: Int(outlets),
                    food: food,
                    volume: volume,
                    accessible: accessible,
                    accessRestriction: access,
                    availableSeats: Int(seats)
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
                        rewardAmount = [Int(seats) != nil, Int(outlets) != nil, food != nil, volume != nil, accessible != nil, access != nil].filter { $0 }.count * 3
                        if rewardAmount > 0 { design.awardPoints(rewardAmount) }
                        showingReward = rewardAmount > 0
                        seats = ""; outlets = ""; food = nil; volume = nil; accessible = nil; access = nil
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        withAnimation { showingUpdate = false; cardOffset = 260 }
                    }
                )
            } label: {
                Text("Submit update")
            }
            .buttonStyle(SagePrimaryButtonStyle())

            Text("Community Spots are shared. Your Wishlist is private to your account.")
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

        // New updates intentionally start blank; past reports remain in the community summary.
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                scrollSnapLocked = false
                if dragStart == nil { dragStart = cardOffset }
                cardOffset = min(340, max(0, (dragStart ?? 260) + value.translation.height))
            }
            .onEnded { value in
                let start = dragStart ?? 260
                dragStart = nil
                if (start == 0 && value.translation.height < -105) || (start >= 200 && value.translation.height > 115) {
                    onClose()
                    return
                }
                let shouldExpand = value.predictedEndTranslation.height < -35 || cardOffset < 130
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    cardOffset = shouldExpand ? 0 : 260
                }
            }
    }
}

private struct CommunitySectionPositionKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Themed choice grid

private struct ThemedChoiceGrid<Value: Hashable & Identifiable & RawRepresentable>: View where Value.RawValue == String {
    let values: [Value]
    let selected: Value?
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

private struct LiveBusyReport {
    let value: Int
    let date: Date
}
