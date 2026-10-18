import Foundation
import StoreKit

@MainActor
public final class PurchaseAccess {
    public static let shared = PurchaseAccess()
    public static let identifiers = ["pro.lifetime", "pro.yearly", "pro.monthly"]

    public private(set) var permanentUnlock: Product?
    public private(set) var recurringPlans: [Product] = []
    public private(set) var entitlements: [Transaction] = []
    public private(set) var premiumAccess = false
    private var observer: Task<Void, Never>?

    public func start() {
        guard observer == nil else { return }
        observer = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update: update)
            }
        }
        Task { [weak self] in
            await self?.loadProducts()
            await self?.refreshEntitlements()
        }
    }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: Self.identifiers)
            permanentUnlock = products.first { $0.type == .nonConsumable }
            recurringPlans = products.filter { $0.type == .autoRenewable }
        } catch {
            NSLog("ray-lite StoreKit: \(error.localizedDescription)")
        }
    }

    func handle(update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else { return }
        entitlements.append(transaction)
        await refreshEntitlements()
        await transaction.finish()
    }

    public func refreshEntitlements() async {
        var pro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.identifiers.contains(transaction.productID) {
                pro = true
            }
        }
        premiumAccess = pro
    }
}

@MainActor
public final class PaywallService {
    public static let shared = PaywallService()

    public var entryQuota = 50
    public var starterEntryQuota = 3
    public var boardQuota = 10
    public var starterBoardQuota = 2
    public var reminderDelays: [TimeInterval] = [0, 120, 600]

    public private(set) var unlockedCanvasesSinceUnboxing: Int = 0
    private var lastNags = [Int: Date]()

    public func limits(newCustomer: Bool) -> (items: Int, canvases: Int) {
        let items = newCustomer ? starterEntryQuota : entryQuota
        let canvases = newCustomer ? starterBoardQuota : boardQuota
        return (items, canvases)
    }

    public func shouldNag(context: Int, now: Date = .init()) -> Bool {
        guard let last = lastNags[context] else {
            lastNags[context] = now
            return true
        }
        let elapsed = now.timeIntervalSince(last)
        if let interval = reminderDelays.first(where: { $0 <= elapsed }) {
            lastNags[context] = now
            return interval > 0 || last == now
        }
        return false
    }
}
