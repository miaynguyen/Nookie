import SwiftUI
import MapKit
import CoreLocation
import Combine
import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

// MARK: - App entry point

@main
struct StudySpotsApp: App {
    @StateObject private var auth = AuthStore()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasSeenOnboarding {
                    OnboardingFlow { hasSeenOnboarding = true }
                } else if auth.user == nil {
                    AuthView()
                } else {
                    MainTabView()
                }
            }
            .environmentObject(auth)
        }
    }
}
// MARK: - Authentication

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var user: User?
    @Published var errorMessage = ""

    private var listener: AuthStateDidChangeListenerHandle?

    init() {
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
            }
        }
    }

    deinit {
        if let listener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }

    func signIn(email: String, password: String) {
        errorMessage = ""
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] _, error in
            Task { @MainActor in
                self?.errorMessage = error?.localizedDescription ?? ""
            }
        }
    }

    func signUp(email: String, password: String) {
        errorMessage = ""
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] _, error in
            Task { @MainActor in
                self?.errorMessage = error?.localizedDescription ?? ""
            }
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AuthView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var showingLogin = false
    @State private var showingSignUp = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()

                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Color(red: 0.35, green: 0.47, blue: 0.41))

                Text("Study Spots")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text("Find, save, and improve places to work.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    Button("Log In") {
                        showingLogin = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Sign Up") {
                        showingSignUp = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .frame(maxWidth: 320)

                if !auth.errorMessage.isEmpty {
                    Text(auth.errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()
                Spacer()
            }
            .padding(24)
        }
        .sheet(isPresented: $showingLogin) {
            AuthForm(mode: .login)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showingSignUp) {
            AuthForm(mode: .signUp)
                .environmentObject(auth)
        }
    }
}

enum AuthFormMode {
    case login
    case signUp
}

struct AuthForm: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore

    let mode: AuthFormMode

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    private var valid: Bool {
        let emailOK = email.contains("@") && email.contains(".")
        let passwordOK = password.count >= 6

        if mode == .signUp {
            return emailOK && passwordOK && password == confirmPassword
        }

        return emailOK && passwordOK
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)

                    if mode == .signUp {
                        SecureField("Confirm password", text: $confirmPassword)
                    }
                }

                Section {
                    Button(mode == .login ? "Log In" : "Create Account") {
                        if mode == .login {
                            auth.signIn(email: email, password: password)
                        } else {
                            auth.signUp(email: email, password: password)
                        }

                        dismiss()
                    }
                    .disabled(!valid)
                }

                if !auth.errorMessage.isEmpty {
                    Section {
                        Text(auth.errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(mode == .login ? "Log In" : "Sign Up")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Models

enum FoodChoice: String, CaseIterable, Identifiable {
    case yes = "Yes"
    case no = "No"
    case specific = "Specific locations"

    var id: String { rawValue }
}

enum AccessRestriction: String, CaseIterable, Identifiable {
    case publicAccess = "Public"
    case membership = "Some membership required"

    var id: String { rawValue }
}

struct CommunityContribution {
    var seats: Int?
    var outlets: Int?
    var food: FoodChoice
    var volume: Int
    var accessible: Bool
    var accessRestriction: AccessRestriction
}

struct CommunitySpot: Identifiable, Hashable {
    let id: String
    var name: String
    var address: String
    var coordinate: CLLocationCoordinate2D
    var hoursText: String
    var contributionCount: Int
    var averageSeats: Int?
    var averageOutlets: Int?
    var communityFood: FoodChoice?
    var averageVolume: Int?
    var communityAccessibility: Bool?
    var communityAccessRestriction: AccessRestriction?

    static func == (lhs: CommunitySpot, rhs: CommunitySpot) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func from(documentID: String, data: [String: Any]) -> CommunitySpot? {
        guard
            let name = data["name"] as? String,
            let address = data["address"] as? String,
            let latitude = data["latitude"] as? Double,
            let longitude = data["longitude"] as? Double
        else {
            return nil
        }

        return CommunitySpot(
            id: documentID,
            name: name,
            address: address,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            hoursText: data["hoursText"] as? String ?? "Hours not provided by MapKit",
            contributionCount: data["contributionCount"] as? Int ?? 0,
            averageSeats: data["averageSeats"] as? Int,
            averageOutlets: data["averageOutlets"] as? Int,
            communityFood: FoodChoice(rawValue: data["communityFood"] as? String ?? ""),
            averageVolume: data["averageVolume"] as? Int,
            communityAccessibility: data["communityAccessibility"] as? Bool,
            communityAccessRestriction: AccessRestriction(rawValue: data["communityAccessRestriction"] as? String ?? "")
        )
    }
}

struct SearchResult: Identifiable, Equatable {
    let id: String
    let mapItem: MKMapItem

    var name: String {
        mapItem.name ?? "Unnamed place"
    }

    var address: String {
        PlaceFormatting.address(from: mapItem.placemark)
    }

    var coordinate: CLLocationCoordinate2D {
        mapItem.placemark.coordinate
    }

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

enum SpotListMode: Hashable {
    case community
    case mySaved
}

// MARK: - Firestore store

@MainActor
final class SpotStore: ObservableObject {
    @Published private(set) var spots: [CommunitySpot] = []
    @Published private(set) var savedSpotIDs: Set<String> = []
    @Published var selectedSpotID: String?
    @Published var errorMessage = ""
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private var spotsListener: ListenerRegistration?
    private var savedIDsListener: ListenerRegistration?

    func listen(mode: SpotListMode, userID: String) {
        stopSpotsListening()
        isLoading = true

        let query: Query
        switch mode {
        case .community:
            query = db.collection("spots").order(by: "name")
        case .mySaved:
            query = db.collection("users")
                .document(userID)
                .collection("savedSpots")
                .order(by: "name")
        }

        spotsListener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }

            Task { @MainActor in
                if let error {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    return
                }

                self.errorMessage = ""
                self.spots = snapshot?.documents.compactMap {
                    CommunitySpot.from(documentID: $0.documentID, data: $0.data())
                } ?? []
                self.isLoading = false
            }
        }
    }

    func listenForSavedSpotIDs(userID: String) {
        savedIDsListener?.remove()

        savedIDsListener = db.collection("users")
            .document(userID)
            .collection("savedSpots")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    if let error {
                        self?.errorMessage = error.localizedDescription
                        return
                    }

                    self?.savedSpotIDs = Set(snapshot?.documents.map(\.documentID) ?? [])
                }
            }
    }

    func stopListening() {
        stopSpotsListening()
        savedIDsListener?.remove()
        savedIDsListener = nil
    }

    private func stopSpotsListening() {
        spotsListener?.remove()
        spotsListener = nil
    }

    func addCommunitySpot(_ result: SearchResult, userID: String, completion: @escaping (CommunitySpot?) -> Void) {
        isLoading = true

        let spotID = Self.makeSpotID(name: result.name, coordinate: result.coordinate)
        let spotRef = db.collection("spots").document(spotID)

        let spotData: [String: Any] = [
            "name": result.name,
            "address": result.address,
            "latitude": result.coordinate.latitude,
            "longitude": result.coordinate.longitude,
            "hoursText": "Hours not provided by MapKit",
            "contributionCount": 0,
            "createdByUID": userID,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        spotRef.getDocument { [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                Task { @MainActor in
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    completion(nil)
                }
                return
            }

            let writeData: [String: Any] = snapshot?.exists == true
                ? ["updatedAt": FieldValue.serverTimestamp()]
                : spotData

            spotRef.setData(writeData, merge: true) { error in
                Task { @MainActor in
                    if let error {
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                        completion(nil)
                        return
                    }

                    self.selectedSpotID = spotID
                    self.isLoading = false
                    self.fetchSpot(spotID, completion: completion)
                }
            }
        }
    }

    func saveToMySaved(spot: CommunitySpot, userID: String, completion: @escaping (Bool) -> Void) {
        guard !userID.isEmpty else {
            completion(false)
            return
        }

        let savedRef = db.collection("users")
            .document(userID)
            .collection("savedSpots")
            .document(spot.id)

        let data: [String: Any] = [
            "spotID": spot.id,
            "name": spot.name,
            "address": spot.address,
            "latitude": spot.coordinate.latitude,
            "longitude": spot.coordinate.longitude,
            "hoursText": spot.hoursText,
            "savedAt": FieldValue.serverTimestamp()
        ]

        savedRef.setData(data, merge: true) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.errorMessage = error.localizedDescription
                    completion(false)
                    return
                }

                self?.savedSpotIDs.insert(spot.id)
                completion(true)
            }
        }
    }

    func fetchSpot(_ spotID: String, completion: @escaping (CommunitySpot?) -> Void) {
        db.collection("spots").document(spotID).getDocument { [weak self] snapshot, error in
            Task { @MainActor in
                if let error {
                    self?.errorMessage = error.localizedDescription
                    completion(nil)
                    return
                }

                completion(snapshot.flatMap {
                    CommunitySpot.from(documentID: $0.documentID, data: $0.data() ?? [:])
                })
            }
        }
    }

    func saveContribution(
        spot: CommunitySpot,
        contribution: CommunityContribution,
        userID: String,
        completion: @escaping () -> Void
    ) {
        isLoading = true

        let contributionRef = db.collection("spots")
            .document(spot.id)
            .collection("contributions")
            .document(userID)

        var data: [String: Any] = [
            "food": contribution.food.rawValue,
            "volume": contribution.volume,
            "accessible": contribution.accessible,
            "accessRestriction": contribution.accessRestriction.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let seats = contribution.seats { data["seats"] = seats }
        if let outlets = contribution.outlets { data["outlets"] = outlets }

        contributionRef.setData(data, merge: true) { [weak self] error in
            guard let self else { return }

            if let error {
                Task { @MainActor in
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
                return
            }

            self.recalculateAggregates(spotID: spot.id) {
                Task { @MainActor in
                    self.isLoading = false
                    completion()
                }
            }
        }
    }

    private func recalculateAggregates(spotID: String, completion: @escaping () -> Void) {
        let ref = db.collection("spots").document(spotID).collection("contributions")

        ref.getDocuments { [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                Task { @MainActor in
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
                return
            }

            let docs = snapshot?.documents ?? []
            let seatValues = docs.compactMap { $0["seats"] as? Int }
            let outletValues = docs.compactMap { $0["outlets"] as? Int }
            let volumeValues = docs.compactMap { $0["volume"] as? Int }

            let avgSeats = Self.roundedAverage(seatValues)
            let avgOutlets = Self.roundedAverage(outletValues)
            let avgVolume = Self.roundedAverage(volumeValues)

            let foodValues = docs.compactMap { $0["food"] as? String }
            let accessibilityValues = docs.compactMap { $0["accessible"] as? Bool }
            let accessValues = docs.compactMap { $0["accessRestriction"] as? String }

            var update: [String: Any] = [
                "contributionCount": docs.count,
                "updatedAt": FieldValue.serverTimestamp()
            ]

            if let avgSeats {
                update["averageSeats"] = avgSeats
            } else {
                update["averageSeats"] = FieldValue.delete()
            }

            if let avgOutlets {
                update["averageOutlets"] = avgOutlets
            } else {
                update["averageOutlets"] = FieldValue.delete()
            }

            if let avgVolume {
                update["averageVolume"] = avgVolume
            } else {
                update["averageVolume"] = FieldValue.delete()
            }

            if let food = Self.mostCommonFood(foodValues) {
                update["communityFood"] = food.rawValue
            } else {
                update["communityFood"] = FieldValue.delete()
            }

            if let accessibility = Self.mostCommonBool(accessibilityValues) {
                update["communityAccessibility"] = accessibility
            } else {
                update["communityAccessibility"] = FieldValue.delete()
            }

            if let access = Self.mostCommonAccess(accessValues) {
                update["communityAccessRestriction"] = access.rawValue
            } else {
                update["communityAccessRestriction"] = FieldValue.delete()
            }

            self.db.collection("spots").document(spotID).setData(update, merge: true) { error in
                Task { @MainActor in
                    if let error {
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                    } else {
                        completion()
                    }
                }
            }
        }
    }

    func fetchMyContribution(spotID: String, userID: String, completion: @escaping (CommunityContribution?) -> Void) {
        db.collection("spots")
            .document(spotID)
            .collection("contributions")
            .document(userID)
            .getDocument { snapshot, _ in
                guard let data = snapshot?.data(), snapshot?.exists == true else {
                    Task { @MainActor in completion(nil) }
                    return
                }

                let contribution = CommunityContribution(
                    seats: data["seats"] as? Int,
                    outlets: data["outlets"] as? Int,
                    food: FoodChoice(rawValue: data["food"] as? String ?? "Yes") ?? .yes,
                    volume: data["volume"] as? Int ?? 3,
                    accessible: data["accessible"] as? Bool ?? true,
                    accessRestriction: AccessRestriction(rawValue: data["accessRestriction"] as? String ?? "Public") ?? .publicAccess
                )

                Task { @MainActor in
                    completion(contribution)
                }
            }
    }

    static func roundedAverage(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    static func mostCommonFood(_ values: [String]) -> FoodChoice? {
        let choices = values.compactMap(FoodChoice.init(rawValue:))
        guard !choices.isEmpty else { return nil }

        let counts = Dictionary(grouping: choices, by: { $0 }).mapValues(\.count)
        let highest = counts.values.max() ?? 0

        // Tie preference: Yes first, then No, then Specific locations.
        return FoodChoice.allCases.first { counts[$0, default: 0] == highest }
    }

    static func mostCommonBool(_ values: [Bool]) -> Bool? {
        guard !values.isEmpty else { return nil }
        let yesCount = values.filter { $0 }.count
        let noCount = values.count - yesCount
        return yesCount >= noCount
    }

    static func mostCommonAccess(_ values: [String]) -> AccessRestriction? {
        let choices = values.compactMap(AccessRestriction.init(rawValue:))
        guard !choices.isEmpty else { return nil }

        let publicCount = choices.filter { $0 == .publicAccess }.count
        let membershipCount = choices.filter { $0 == .membership }.count

        // Tie preference: Public.
        return publicCount >= membershipCount ? .publicAccess : .membership
    }

    static func makeSpotID(name: String, coordinate: CLLocationCoordinate2D) -> String {
        let normalized = "\(name.lowercased())|\(String(format: "%.5f", coordinate.latitude))|\(String(format: "%.5f", coordinate.longitude))"
        let allowed = normalized.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return character
            }
            return "_"
        }
        return String(allowed).prefix(120).description
    }
}

// MARK: - Map search

@MainActor
final class MapSearchModel: ObservableObject {
    @Published var query = ""
    @Published var results: [SearchResult] = []
    @Published var errorMessage = ""
    @Published var isSearching = false

    func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }

        isSearching = true
        errorMessage = ""

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.pointOfInterest, .address]

        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            Task { @MainActor in
                self?.isSearching = false

                if let error {
                    self?.errorMessage = error.localizedDescription
                    self?.results = []
                    return
                }

                self?.results = response?.mapItems.prefix(8).map {
                    SearchResult(
                        id: SpotStore.makeSpotID(
                            name: $0.name ?? "place",
                            coordinate: $0.placemark.coordinate
                        ),
                        mapItem: $0
                    )
                } ?? []
            }
        }
    }
}

// MARK: - Main screen

struct StudySpotsView: View {
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

    private let mapTint = Color(red: 0.35, green: 0.47, blue: 0.41)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 10)

                    modePicker
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)

                    mapView
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                }
                .background(Color(.systemBackground))

                if let selectedSpot {
                    CommunitySpotCard(
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
                    .frame(height: min(geometry.size.height * 0.70, 640))
                    .padding(.horizontal, 10)
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
                focusMap(on: spot)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("Study Spots")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(.label))

                Spacer()

                Button {
                    auth.signOut()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .accessibilityLabel("Log out")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search campus, library, or café", text: $search.query)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .submitLabel(.search)
                    .onSubmit {
                        search.search()
                    }

                if search.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.systemGray4), lineWidth: 1.3)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 3)

            if !search.results.isEmpty {
                SearchResultsOverlay(
                    results: search.results,
                    onSelect: { result in
                        guard let uid = auth.user?.uid else { return }
                        search.results = []
                        search.query = result.name

                        // Search results are added to the shared Community Spots first.
                        // They are NOT automatically added to My Saved.
                        store.addCommunitySpot(result, userID: uid) { spot in
                            guard let spot else { return }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                selectedSpot = spot
                                cardOffset = 260
                            }
                            focusMap(on: spot)
                        }
                    }
                )
            }
        }
    }

    private var modePicker: some View {
        Picker("Spot source", selection: $mode) {
            Text("Community Spots").tag(SpotListMode.community)
            Text("My Saved").tag(SpotListMode.mySaved)
        }
        .pickerStyle(.segmented)
        .tint(mapTint)
    }

    private var mapView: some View {
        Map(position: $cameraPosition) {
            ForEach(Array(store.spots.enumerated()), id: \.element.id) { index, spot in
                Annotation("", coordinate: spot.coordinate) {
                    SpotPin(
                        number: mode == .mySaved ? index + 1 : nil,
                        isSelected: selectedSpot?.id == spot.id,
                        tint: mapTint
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

    private func focusMap(on spot: CommunitySpot) {
        focusMap(on: spot.coordinate)
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

struct SearchResultsOverlay: View {
    let results: [SearchResult]
    let onSelect: (SearchResult) -> Void

    private let tint = Color(red: 0.35, green: 0.47, blue: 0.41)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(results) { result in
                Button {
                    onSelect(result)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title3)
                            .foregroundStyle(tint)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(result.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Text("Add")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if result.id != results.last?.id {
                    Divider().padding(.leading, 48)
                }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 14, y: 8)
    }
}

// MARK: - Map pin

struct SpotPin: View {
    let number: Int?
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(tint)
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.18), radius: 5, y: 3)

                if let number {
                    Text("\(number)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "mappin")
                        .foregroundStyle(.white)
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .overlay {
                Circle()
                    .stroke(.white, lineWidth: 3)
            }
            .scaleEffect(isSelected ? 1.28 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Community card

struct CommunitySpotCard: View {
    let spot: CommunitySpot
    @ObservedObject var store: SpotStore
    let userID: String
    @Binding var cardOffset: CGFloat
    let onDirections: () -> Void
    let onClose: () -> Void

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

    private let tint = Color(red: 0.35, green: 0.47, blue: 0.41)

    var body: some View {
        let displaySpot = liveSpot

        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.systemGray3))
                .frame(width: 42, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .contentShape(Rectangle())
                .gesture(dragGesture)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(displaySpot.name)
                                .font(.title3.bold())
                                .lineLimit(2)

                            Text(displaySpot.address)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if store.savedSpotIDs.contains(displaySpot.id) {
                        Label("Saved to My Saved", systemImage: "bookmark.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(tint)
                    } else {
                        Button {
                            store.saveToMySaved(spot: displaySpot, userID: userID) { _ in }
                        } label: {
                            HStack {
                                Image(systemName: "bookmark")
                                Text("Save to My Saved")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(tint)
                            .background(tint.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onDirections) {
                        HStack {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            Text("Directions")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(tint)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    infoBlock(title: "Business hours", value: displaySpot.hoursText)
                    infoBlock(title: "Community updates", value: "\(displaySpot.contributionCount)")
                    infoBlock(title: "Number of seats (estimate)", value: displaySpot.averageSeats.map(String.init) ?? "—")
                    infoBlock(title: "Number of outlets", value: displaySpot.averageOutlets.map(String.init) ?? "—")

                    Divider()

                    // This is deliberately separate from the user's own update form.
                    Text("Community updates")
                        .font(.headline)

                    Text("Current community consensus from all submitted updates")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    communityRow(
                        title: "Food allowed",
                        value: displaySpot.communityFood?.rawValue ?? "No updates yet"
                    )

                    communityRow(
                        title: "Volume level",
                        value: displaySpot.averageVolume.map { "\($0)/5" } ?? "No updates yet"
                    )

                    communityRow(
                        title: "Accessibility",
                        value: displaySpot.communityAccessibility.map { $0 ? "Yes" : "No" } ?? "No updates yet"
                    )

                    communityRow(
                        title: "Access restrictions",
                        value: displaySpot.communityAccessRestriction?.rawValue ?? "No updates yet"
                    )

                    Divider()

                    Text("Add your community update")
                        .font(.headline)

                    HStack(spacing: 12) {
                        numericField(title: "Seats", text: $seats)
                        numericField(title: "Outlets", text: $outlets)
                    }

                    optionSection(title: "Food allowed") {
                        ChoiceGrid(values: FoodChoice.allCases, selected: food, tint: tint) { value in
                            food = value
                        }
                    }

                    optionSection(title: "Volume level") {
                        HStack(spacing: 12) {
                            ForEach(1...5, id: \.self) { value in
                                Button {
                                    volume = value
                                } label: {
                                    Circle()
                                        .fill(value <= volume ? tint : Color(.systemGray5))
                                        .frame(width: 36, height: 36)
                                        .overlay {
                                            Text("\(value)")
                                                .font(.caption.bold())
                                                .foregroundStyle(value <= volume ? .white : .secondary)
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    optionSection(title: "Accessibility") {
                        BinaryChoice(isOn: accessible, tint: tint) {
                            accessible = true
                        } offAction: {
                            accessible = false
                        }
                    }

                    optionSection(title: "Access restrictions") {
                        ChoiceGrid(values: AccessRestriction.allCases, selected: access, tint: tint) { value in
                            access = value
                        }
                    }

                    Button {
                        hideKeyboard()
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
                            }
                        )
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Submit community update")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)

                    Text("Everyone shares Community Spots. My Saved is private to the signed-in account.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                hideKeyboard()
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 22, y: -6)
        .offset(y: cardOffset)
        .onAppear {
            loadCurrentData()
        }
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

    private func infoBlock(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }

    private func communityRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }

    private func numericField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Estimate", text: text)
                .keyboardType(.numberPad)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity)
    }

    private func optionSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
    }
}

struct ChoiceGrid<Value: Hashable & Identifiable & RawRepresentable>: View where Value.RawValue == String {
    let values: [Value]
    let selected: Value
    let tint: Color
    let action: (Value) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
            ForEach(values) { value in
                Button {
                    action(value)
                } label: {
                    Text(value.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selected == value ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selected == value ? tint : Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct BinaryChoice: View {
    let isOn: Bool
    let tint: Color
    let onAction: () -> Void
    let offAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("Yes", action: onAction)
                .buttonStyle(.borderedProminent)
                .tint(isOn ? tint : .gray)

            Button("No", action: offAction)
                .buttonStyle(.borderedProminent)
                .tint(!isOn ? tint : .gray)
        }
    }
}

// MARK: - Directions

struct DirectionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let spot: CommunitySpot

    var body: some View {
        NavigationStack {
            List {
                Section(spot.name) {
                    Text(spot.address)
                        .foregroundStyle(.secondary)
                }

                Section("Open directions in Apple Maps") {
                    directionButton(title: "Walking", systemImage: "figure.walk", mode: MKLaunchOptionsDirectionsModeWalking)
                    directionButton(title: "Driving", systemImage: "car.fill", mode: MKLaunchOptionsDirectionsModeDriving)
                    directionButton(title: "Transit", systemImage: "tram.fill", mode: MKLaunchOptionsDirectionsModeTransit)
                }
            }
            .navigationTitle("Directions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func directionButton(title: String, systemImage: String, mode: String) -> some View {
        Button {
            let destination = MKMapItem(placemark: MKPlacemark(coordinate: spot.coordinate))
            let options: [String: Any] = [
                MKLaunchOptionsDirectionsModeKey: mode
            ]

            MKMapItem.openMaps(
                with: [destination],
                launchOptions: options
            )
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

// MARK: - Helpers

enum PlaceFormatting {
    static func address(from placemark: CLPlacemark) -> String {
        let pieces = [
            placemark.subThoroughfare,
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode,
            placemark.country
        ].compactMap { $0 }

        return pieces.isEmpty ? (placemark.name ?? "Address unavailable") : pieces.joined(separator: ", ")
    }
}

private func hideKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}

