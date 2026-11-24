#if os(iOS) && DEBUG
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import Cadence

/// **A list's Tasks tab is as tall at the bottom of its scroll as at the top ([[T-19922]]).**
///
/// Grouped By Section, the seeded `[Sample] TestFlight Readiness` froze on the iPhone when swiped:
/// the main thread sat at ~100% inside SwiftUI's lazy placement. Its groups were the children of a
/// `LazyVStack` -- an empty Default heading over groups hundreds of points tall -- and a lazy stack
/// sizes the children it has not built from the ones it has, so the page measured 930pt from the
/// top and 762pt from the bottom. The groups are an eager `VStack` now (rows stay lazy inside
/// `iOSTaskGroupSection`), and the height no longer depends on where the page is scrolled.
///
/// Hosted for real: the page, in a window on the test host's scene, scrolled by its own
/// `UIScrollView`. A COUNT relation, never a duration or a pinned figure: the content height read
/// at the top, at the bottom and back at the top must be one number.
@MainActor
struct iOSListDetailTasksScrollHeightTests {
    @Test func theBySectionTasksTabIsAsTallAtTheBottomAsAtTheTop() throws {
        let heights = try contentHeights(grouping: .byList)
        #expect(Set(heights).count == 1, "the Tasks tab's height moved with its scroll: \(heights)")
    }

    /// The control: By Date's groups are alike, and its height never moved even before the fix.
    @Test func theByDateTasksTabIsAsTallAtTheBottomAsAtTheTop() throws {
        let heights = try contentHeights(grouping: .byDate)
        #expect(Set(heights).count == 1, "the Tasks tab's height moved with its scroll: \(heights)")
    }

    /// The page's scroll content height at the top, at the bottom, and back at the top.
    private func contentHeights(grouping: TaskGroupingMode) throws -> [Int] {
        let container = try CadenceTestStore.container()
        let context = container.mainContext
        try iOSSampleDataSupport.seedReviewTasks(allTasks: [], modelContext: context)
        try context.save()
        let project = try #require(
            try context.fetch(FetchDescriptor<Project>()).first { $0.name == "[Sample] TestFlight Readiness" }
        )
        // Keyed by this store's own project id, so no other list's remembered grouping is touched.
        let key = ListDetailSortControls.groupingKey(
            ListDetailSortControls.tasksKeyPrefix(areaID: nil, projectID: project.id)
        )
        CadenceDefaults.store.set(grouping.rawValue, forKey: key)
        defer { CadenceDefaults.store.removeObject(forKey: key) }

        let host = UIHostingController(
            rootView: iOSListDetailView(project: project)
                .environment(CadenceDeepLinkManager.shared)
                .modelContainer(container)
        )
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        // The owner's iPhone 15, in points.
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 760)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        settle()

        let scrollView = try #require(
            scrollViews(in: host.view).max { $0.contentSize.height < $1.contentSize.height },
            "the Tasks tab drew no scroll view"
        )
        var heights = [Int(scrollView.contentSize.height)]
        // Taller than the viewport, or there is no bottom to scroll to and the test proves nothing.
        try #require(scrollView.contentSize.height > scrollView.bounds.height + 100, "\(heights)")
        let bottom = scrollView.contentSize.height - scrollView.bounds.height
            + scrollView.adjustedContentInset.bottom
        scrollView.setContentOffset(CGPoint(x: 0, y: bottom), animated: true)
        settle()
        // Asked again from wherever the first request landed: a page that shrank on the way down
        // has a nearer bottom, and that is the page the reader is now looking at.
        let landed = scrollView.contentSize.height - scrollView.bounds.height
            + scrollView.adjustedContentInset.bottom
        scrollView.setContentOffset(CGPoint(x: 0, y: landed), animated: false)
        settle()
        heights.append(Int(scrollView.contentSize.height))
        scrollView.setContentOffset(.zero, animated: true)
        settle()
        heights.append(Int(scrollView.contentSize.height))
        return heights
    }

    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        var found: [UIScrollView] = []
        if let scrollView = view as? UIScrollView { found.append(scrollView) }
        for subview in view.subviews { found += scrollViews(in: subview) }
        return found
    }
}
#endif
