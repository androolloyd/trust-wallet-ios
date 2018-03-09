// Copyright SIX DAY LLC. All rights reserved.

import UIKit
import APIKit
import JSONRPCKit
import StatefulViewController
import Result
import TrustKeystore

protocol TransactionsViewControllerDelegate: class {
    func didPressSend(in viewController: TransactionsViewController)
    func didPressRequest(in viewController: TransactionsViewController)
    func didPressTransaction(transaction: Transaction, in viewController: TransactionsViewController)
    func didPressDeposit(for account: Wallet, sender: UIView, in viewController: TransactionsViewController)
}

class TransactionsViewController: UIViewController {

    var viewModel: TransactionsViewModel

    let account: Wallet

    let tableView = UITableView(frame: .zero, style: .plain)
    let refreshControl = UIRefreshControl()

    lazy var titleView: BalanceTitleView = {
        return BalanceTitleView.make(from: self.session, .ether(destination: .none))
    }()

    weak var delegate: TransactionsViewControllerDelegate?

    var timer: Timer?
    
    var updateTransactionsTimer: Timer?

    let session: WalletSession

    lazy var footerView: TransactionsFooterView = {
        let footerView = TransactionsFooterView(frame: .zero)
        footerView.translatesAutoresizingMaskIntoConstraints = false
        footerView.requestButton.addTarget(self, action: #selector(request), for: .touchUpInside)
        footerView.sendButton.addTarget(self, action: #selector(send), for: .touchUpInside)
        return footerView
    }()

    let insets = UIEdgeInsets(top: 130, left: 0, bottom: ButtonSize.extraLarge.height + 84, right: 0)

    init(
        account: Wallet,
        session: WalletSession,
        viewModel: TransactionsViewModel
    ) {
        self.account = account
        self.session = session
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)

        view.backgroundColor = viewModel.backgroundColor
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .white
        tableView.rowHeight = 68
        view.addSubview(tableView)
        view.addSubview(footerView)

        NSLayoutConstraint.activate([
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerView.bottomAnchor.constraint(equalTo: view.layoutGuide.bottomAnchor),
        ])

        viewModel.fetch()

        refreshControl.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        tableView.addSubview(refreshControl)

        errorView = ErrorView(insets: insets, onRetry: { [weak self] in
            self?.startLoading()
            self?.viewModel.fetch()
        })
        loadingView = LoadingView(insets: insets)
        emptyView = {
            let view = TransactionsEmptyView(
                insets: insets,
                onDeposit: { [unowned self] sender in
                    self.showDeposit(sender)
                }
            )
            view.isDepositAvailable = viewModel.isBuyActionAvailable
            return view
        }()

        navigationItem.titleView = titleView
        titleView.viewModel = BalanceViewModel()

        NotificationCenter.default.addObserver(self, selector: #selector(TransactionsViewController.stopTimers), name: .UIApplicationWillResignActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TransactionsViewController.restartTimers), name: .UIApplicationDidBecomeActive, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        fetch()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    @objc func pullToRefresh() {
        refreshControl.beginRefreshing()
        fetch()
    }

    func fetch() {
        startLoading()
        viewModel.fetch()
    }

    @objc func send() {
        delegate?.didPressSend(in: self)
    }

    @objc func request() {
        delegate?.didPressRequest(in: self)
    }

    func showDeposit(_ sender: UIButton) {
        delegate?.didPressDeposit(for: account, sender: sender, in: self)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func stopTimers() {
        timer?.invalidate()
        timer = nil
        updateTransactionsTimer?.invalidate()
        updateTransactionsTimer = nil
    }
    
    @objc func restartTimers() {
        runScheduledTimers()
    }

    private func runScheduledTimers() {
        guard timer == nil, updateTransactionsTimer == nil else {
            return
        }
        timer = Timer.scheduledTimer(timeInterval: 5, target: BlockOperation { [weak self] in
            self?.viewModel.fetchPending()
        }, selector: #selector(Operation.main), userInfo: nil, repeats: true)
        updateTransactionsTimer = Timer.scheduledTimer(timeInterval: 15, target: BlockOperation { [weak self] in
            self?.viewModel.fetchTransactions()
        }, selector: #selector(Operation.main), userInfo: nil, repeats: true)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension TransactionsViewController: StatefulViewController {
    func hasContent() -> Bool {
        return viewModel.numberOfSections > 0
    }
}

extension TransactionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true )
        delegate?.didPressTransaction(transaction: viewModel.item(for: indexPath.row, section: indexPath.section), in: self)
    }
}

extension TransactionsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel.numberOfSections
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let transaction = viewModel.item(for: indexPath.row, section: indexPath.section)
        let cell = TransactionViewCell(style: .default, reuseIdentifier: TransactionViewCell.identifier)
        cell.configure(viewModel: .init(
                transaction: transaction,
                config: session.config,
                chainState: session.chainState,
                currentWallet: session.account
            )
        )
        return cell
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.numberOfItems(for: section)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return viewModel.hederView(for: section)
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        view.layer.addBorder(edge: .top, color: viewModel.headerBorderColor, thickness: 0.5)
        view.layer.addBorder(edge: .bottom, color: viewModel.headerBorderColor, thickness: 0.5)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return StyleLayout.TableView.heightForHeaderInSection
    }
}
