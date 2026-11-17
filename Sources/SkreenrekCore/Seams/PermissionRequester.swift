/// Permission requests are explicit user actions. Probing permissions never calls this seam.
@MainActor
public protocol PermissionRequester: Sendable {
    func request(_ permission: Permission)
}
