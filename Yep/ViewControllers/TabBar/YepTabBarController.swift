//
//  YepTabBarController.swift
//  Yep
//
//  Created by kevinzhow on 15/3/28.
//  Copyright (c) 2015年 Catch Inc. All rights reserved.
//

import UIKit
import YepKit
import Proposer

final class YepTabBarController: UITabBarController {

    enum Tab: Int {

        case Conversations
        case Contacts
        case Feeds
        case Discover
        case Profile

        var title: String {

            switch self {
            case .Conversations:
                return String.trans_titleChats
            case .Contacts:
                return String.trans_titleContacts
            case .Feeds:
                return String.trans_titleFeeds
            case .Discover:
                return String.trans_titleDiscover
            case .Profile:
                return NSLocalizedString("Profile", comment: "")
            }
        }
    }

    private var previousTab: Tab = .Conversations
    var tab: Tab? {
        didSet {
            if let tab = tab {
                self.selectedIndex = tab.rawValue
            }
        }
    }

    private var checkDoubleTapOnFeedsTimer: NSTimer?
    private var hasFirstTapOnFeedsWhenItIsAtTop = false {
        willSet {
            checkDoubleTapOnFeedsTimer?.invalidate()

            if newValue {
                let timer = NSTimer.scheduledTimerWithTimeInterval(0.5, target: self, selector: #selector(YepTabBarController.checkDoubleTapOnFeeds(_:)), userInfo: nil, repeats: false)
                checkDoubleTapOnFeedsTimer = timer
            }
        }
    }

    @objc private func checkDoubleTapOnFeeds(timer: NSTimer) {

        hasFirstTapOnFeedsWhenItIsAtTop = false
    }

    private struct Listener {
        static let lauchStyle = "YepTabBarController.lauchStyle"
    }

    private let tabBarItemTextEnabledListenerName = "YepTabBarController.tabBarItemTextEnabled"

    deinit {
        checkDoubleTapOnFeedsTimer?.invalidate()

        if let appDelegate = UIApplication.sharedApplication().delegate as? AppDelegate {
            appDelegate.lauchStyle.removeListenerWithName(Listener.lauchStyle)
        }

        YepUserDefaults.tabBarItemTextEnabled.removeListenerWithName(tabBarItemTextEnabledListenerName)

        println("deinit YepTabBar")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self

        view.backgroundColor = UIColor.whiteColor()

        YepUserDefaults.tabBarItemTextEnabled.bindAndFireListener(tabBarItemTextEnabledListenerName) { [weak self] _ in
            self?.adjustTabBarItems()
        }

        // 处理启动切换

        if let appDelegate = UIApplication.sharedApplication().delegate as? AppDelegate {
            appDelegate.lauchStyle.bindListener(Listener.lauchStyle) { [weak self] style in
                if style == .Message {
                    self?.selectedIndex = 0
                }
            }
        }

        delay(3) {
            if PrivateResource.Location(.WhenInUse).isAuthorized {
                YepLocationService.turnOn()
            }
        }
    }

    func adjustTabBarItems() {

        let noNeedTitle: Bool
        if let tabBarItemTextEnabled = YepUserDefaults.tabBarItemTextEnabled.value {
            noNeedTitle = !tabBarItemTextEnabled
        } else {
            noNeedTitle = YepUserDefaults.appLaunchCount.value > YepUserDefaults.appLaunchCountThresholdForTabBarItemTextEnabled
        }

        if noNeedTitle {
            // 将 UITabBarItem 的 image 下移一些，也不显示 title 了
            if let items = tabBar.items {
                for item in items {
                    item.imageInsets = UIEdgeInsetsMake(6, 0, -6, 0)
                    item.title = nil
                }
            }

        } else {
            // Set Titles
            if let items = tabBar.items {
                for i in 0..<items.count {
                    let item = items[i]
                    item.imageInsets = UIEdgeInsetsZero
                    item.title = Tab(rawValue: i)?.title
                }
            }
        }
    }

    var isTabBarVisible: Bool {
        return self.tabBar.frame.origin.y < CGRectGetMaxY(view.frame)
    }

    func setTabBarHidden(hidden: Bool, animated: Bool) {

        guard isTabBarVisible == hidden else {
            return
        }

        let height = self.tabBar.frame.size.height
        let offsetY = (hidden ? height : -height)

        let duration = (animated ? 0.25 : 0.0)

        UIView.animateWithDuration(duration, animations: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            let frame = strongSelf.tabBar.frame
            strongSelf.tabBar.frame = CGRectOffset(frame, 0, offsetY)
        }, completion: nil)
    }
}

// MARK: - UITabBarControllerDelegate

extension YepTabBarController: UITabBarControllerDelegate {

    func tabBarController(tabBarController: UITabBarController, shouldSelectViewController viewController: UIViewController) -> Bool {

        guard
            let tab = Tab(rawValue: selectedIndex),
            let nvc = viewController as? UINavigationController else {
                return false
        }

        if tab != previousTab {
            return true
        }

        if case .Feeds = tab {
            if let vc = nvc.topViewController as? FeedsViewController {
                if vc.scrollView.yep_isAtTop {
                    if !hasFirstTapOnFeedsWhenItIsAtTop {
                        hasFirstTapOnFeedsWhenItIsAtTop = true
                        return false
                    }
                }
            }
        }

        return true
    }

    func tabBarController(tabBarController: UITabBarController, didSelectViewController viewController: UIViewController) {

        guard
            let tab = Tab(rawValue: selectedIndex),
            let nvc = viewController as? UINavigationController else {
                return
        }

        if tab != .Contacts {
            NSNotificationCenter.defaultCenter().postNotificationName(YepConfig.Notification.switchedToOthersFromContactsTab, object: nil)
        }

        // 不相等才继续，确保第一次 tap 不做事
        if tab != previousTab {
            previousTab = tab
            return
        }

        if let vc = nvc.topViewController as? CanScrollsToTop {

            vc.scrollsToTopIfNeed(otherwise: { [weak self, weak vc] in
                // 只特别处理 Feeds
                guard let vc = vc as? FeedsViewController else { return }

                if !vc.feeds.isEmpty && !vc.pullToRefreshView.isRefreshing {
                    vc.scrollView.setContentOffset(CGPoint(x: 0, y: -150), animated: true)
                    self?.hasFirstTapOnFeedsWhenItIsAtTop = false
                }
            })
        }

        /*
        switch tab {

        case .Conversations:
            if let vc = nvc.topViewController as? CanScrollsToTop {
                vc.scrollsToTopIfNeed()
            }

        case .Contacts:
            if let vc = nvc.topViewController as? CanScrollsToTop {
                vc.scrollsToTopIfNeed()
            }

        case .Feeds:
            if let vc = nvc.topViewController as? CanScrollsToTop {
                vc.scrollsToTopIfNeed(otherwise: { [weak self, weak vc] in
                    guard let vc = vc as? FeedsViewController else { return }
                    if !vc.feeds.isEmpty && !vc.pullToRefreshView.isRefreshing {
                        vc.scrollView.setContentOffset(CGPoint(x: 0, y: -150), animated: true)
                        self?.hasFirstTapOnFeedsWhenItIsAtTop = false
                    }
                    })
            }

        case .Discover:
            if let vc = nvc.topViewController as? CanScrollsToTop {
                vc.scrollsToTopIfNeed()
            }

        case .Profile:
            if let vc = nvc.topViewController as? CanScrollsToTop {
                vc.scrollsToTopIfNeed()
            }
        }
        */
    }
}

