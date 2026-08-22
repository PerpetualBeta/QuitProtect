public final class EventTapLifecycleController<Resource> {
    public typealias Create = () -> Resource?
    public typealias Inspect = (Resource) -> Bool
    public typealias Enable = (Resource) -> Void
    public typealias Destroy = (Resource) -> Void

    private let create: Create
    private let isValid: Inspect
    private let isEnabled: Inspect
    private let enable: Enable
    private let destroy: Destroy
    private var resource: Resource?

    public init(
        create: @escaping Create,
        isValid: @escaping Inspect,
        isEnabled: @escaping Inspect,
        enable: @escaping Enable,
        destroy: @escaping Destroy
    ) {
        self.create = create
        self.isValid = isValid
        self.isEnabled = isEnabled
        self.enable = enable
        self.destroy = destroy
    }

    public var isProtecting: Bool {
        guard let resource else { return false }
        return isValid(resource) && isEnabled(resource)
    }

    @discardableResult
    public func start() -> Bool {
        if isProtecting { return true }
        tearDown()

        guard let candidate = create() else { return false }
        resource = candidate
        enable(candidate)

        guard isValid(candidate), isEnabled(candidate) else {
            tearDown()
            return false
        }
        return true
    }

    /// Re-enable the current tap when possible. If macOS has invalidated it, or enabling it does
    /// not restore protection, dispose of the complete tap/source pair and build a fresh pair.
    @discardableResult
    public func recoverAfterDisable() -> Bool {
        if let resource, isValid(resource) {
            enable(resource)
            if isValid(resource), isEnabled(resource) { return true }
        }
        tearDown()
        return start()
    }

    public func stop() {
        tearDown()
    }

    private func tearDown() {
        guard let resource else { return }
        self.resource = nil
        destroy(resource)
    }
}
