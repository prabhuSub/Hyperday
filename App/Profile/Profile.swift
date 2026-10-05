import AuthenticationServices
import PhotosUI
import SwiftUI
import UIKit

/// v14 profile: Sign in with Apple (name + email) and an optional photo you pick.
/// Apple never shares the Apple ID photo, so the circle shows initials until you choose one.
@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published var name: String? { didSet { d.set(name, forKey: "profileName") } }
    @Published var email: String? { didSet { d.set(email, forKey: "profileEmail") } }
    @Published var userID: String? { didSet { d.set(userID, forKey: "profileAppleID") } }
    @Published var photo: UIImage?

    private let d = UserDefaults.standard
    private let photoURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("profile-photo.jpg")

    private init() {
        name = d.string(forKey: "profileName")
        email = d.string(forKey: "profileEmail")
        userID = d.string(forKey: "profileAppleID")
        photo = (try? Data(contentsOf: photoURL)).flatMap(UIImage.init(data:))
    }

    var signedIn: Bool { userID != nil }

    /// Set HyperdaySignInWithApple = YES in Info.plist (project.yml) after enrolling and adding the
    /// com.apple.developer.applesignin entitlement; a free Apple ID can't sign it.
    nonisolated static var signInAvailable: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "HyperdaySignInWithApple") as? Bool) ?? false
    }

    var initials: String {
        let parts = (name ?? "").split(separator: " ")
        let s = parts.prefix(2).compactMap(\.first).map(String.init).joined()
        return s.isEmpty ? "" : s.uppercased()
    }

    func setPhoto(_ image: UIImage?) {
        let image = image.map { Self.shrink($0, to: 256) }
        photo = image
        if let data = image?.jpegData(compressionQuality: 0.85) {
            try? data.write(to: photoURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: photoURL)
        }
    }

    /// A 12 MP photo decoded for a 32pt avatar costs ~48 MB; 256 px is plenty.
    private static func shrink(_ image: UIImage, to side: CGFloat) -> UIImage {
        let s = image.size
        guard max(s.width, s.height) > side else { return image }
        let k = side / max(s.width, s.height)
        let size = CGSize(width: s.width * k, height: s.height * k)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    func handle(_ result: Result<ASAuthorization, Error>) -> String? {
        switch result {
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return nil }
            userID = cred.user
            // Apple sends the name and email only the first time you sign in; keep what we have after that.
            if let n = cred.fullName, let formatted = PersonNameComponentsFormatter().string(for: n), !formatted.isEmpty {
                name = formatted
            }
            if let e = cred.email { email = e }
            return nil
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return nil }
            return "Sign in with Apple isn't available on this build (it needs the Apple Developer Program). \(error.localizedDescription)"
        }
    }

    func signOut() {
        userID = nil
        email = nil
    }

    /// If you revoked Hyperday in Settings › Apple ID, sign out here too.
    func checkStillValid() {
        guard let id = userID else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: id) { state, _ in
            if state == .revoked || state == .notFound {
                Task { @MainActor in ProfileStore.shared.signOut() }
            }
        }
    }
}

/// The circle at the top right of every tab.
struct ProfileButton: View {
    @ObservedObject private var profile = ProfileStore.shared
    let action: () -> Void

    var body: some View {
        Button(action: action) { ProfileAvatar(size: 32) }
            .buttonStyle(.plain)
            .accessibilityLabel(profile.name.map { "Profile, \($0)" } ?? "Profile")
    }
}

struct ProfileAvatar: View {
    @ObservedObject private var profile = ProfileStore.shared
    var size: CGFloat

    var body: some View {
        Group {
            if let photo = profile.photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else if !profile.initials.isEmpty {
                LinearGradient(colors: [Theme.red, Color(red: 0.54, green: 0.06, blue: 0.13)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Text(profile.initials)
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(.white))
            } else {
                Theme.border.overlay(HDIcon("personal", size: size * 0.5).foregroundStyle(Theme.muted))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct ProfileSheet: View {
    @ObservedObject private var profile = ProfileStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var pick: PhotosPickerItem?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if profile.signedIn {
                        signedIn
                    } else {
                        signedOut
                    }
                    if let error {
                        Text(error).font(.system(size: 12)).foregroundStyle(Theme.red)
                    }
                    Text("Apple shares only your name and an email (you can hide it). It never shares your Apple ID photo, so the circle shows your initials until you pick a photo.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                }
                .padding(20)
            }
            .background(Theme.section)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: pick) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        profile.setPhoto(img)
                    }
                }
            }
            .onAppear { profile.checkStillValid() }
        }
    }

    private var signedOut: some View {
        VStack(spacing: 12) {
            ProfileAvatar(size: 72)
            Text(profile.name ?? (ProfileStore.signInAvailable ? "Not signed in" : "Your profile")).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.text)
            Text("Sign in to put your name on Hyperday and get ready for iCloud sync across your devices.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            if ProfileStore.signInAvailable {
            SignInWithAppleButton(.signIn) { req in
                req.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                error = profile.handle(result)
            }
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Sign in with Apple turns on once you join the Apple Developer Program.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
            photoRow.padding(.top, 6)
        }
        .padding(.vertical, 8)
        .cardBox()
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ProfileAvatar(size: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name ?? "Signed in").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
                    Label("Signed in with Apple", systemImage: "applelogo")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.bottom, 10)
            row("Email", profile.email ?? "Hidden")
            photoRow
            Button("Sign out", role: .destructive) { profile.signOut() }
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
        .cardBox()
    }

    private var photoRow: some View {
        HStack {
            Text("Photo").font(.system(size: 14)).foregroundStyle(Theme.text)
            Spacer()
            if profile.photo != nil {
                Button("Remove") { profile.setPhoto(nil) }.font(.system(size: 14))
            }
            let label = profile.photo == nil ? "Choose…" : "Change"
            PhotosPicker(selection: $pick, matching: .images) {
                Text(label).font(.system(size: 14))
            }
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func row(_ a: String, _ b: String) -> some View {
        HStack {
            Text(a).font(.system(size: 14)).foregroundStyle(Theme.text)
            Spacer()
            Text(b).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}
