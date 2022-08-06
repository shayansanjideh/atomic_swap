/// User 0 deposits x amount of coin X into an escrow, with the expectation that if someone deposits y amount of coin Y,
/// both users will recieve the opposite amount of each coin

module atomic_swap::atomic_swap {

    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::account;
    use aptos_framework::managed_coin;

    struct Escrow<phantom X, phantom Y> has key {
        coin_x: coin::Coin<X>,
        amt_x: u64,
        coin_y: coin::Coin<Y>,
        req_y: u64
    }

    struct EscrowEvent has key {
        escrow_addr: address
    }

    const ECOIN_NOT_INIT: u64 = 0;
    const EESCROW_NOT_INIT: u64 = 1;
    const EINCORRECT_BALANCE: u64 = 2;

    /// Initialize escrow
    public entry fun init_escrow<X, Y>(init_user: &signer, seed: vector<u8>) {
        let init_user_addr = signer::address_of(init_user);

        if (!coin::is_account_registered<X>(init_user_addr)) {
            coin::register<X>(init_user);
        };
        if (!coin::is_account_registered<Y>(init_user_addr)) {
            coin::register<Y>(init_user);
        };

        let (escrow_signer, _escrow_signer_cap) = account::create_resource_account(init_user, seed);

        // Register the escrow to be able to accept both coins
        coin::register<X>(&escrow_signer);
        coin::register<Y>(&escrow_signer);

        move_to(
            &escrow_signer,
            Escrow<X, Y> {
                coin_x: coin::zero<X>(),
                amt_x: 0,
                coin_y: coin::zero<Y>(),
                req_y: 0
            }
        );
        let escrow_addr = signer::address_of(&escrow_signer);
        move_to(init_user, EscrowEvent { escrow_addr });
    }

    /// Initiate swap: immediately after initializing the escrow, the user should deposit their desired amount of coin
    /// X and specify the amount of coin Y they want in return
    public entry fun init_swap<X, Y>(init_user: &signer, amt_x: u64, amt_y: u64)
    acquires Escrow, EscrowEvent {
        let init_user_addr = signer::address_of(init_user);
        let escrow_addr = borrow_global<EscrowEvent>(init_user_addr).escrow_addr;
        assert!(exists<Escrow<X, Y>>(escrow_addr), EESCROW_NOT_INIT);

        let dep_x = copy amt_x;
        coin::transfer<X>(init_user, escrow_addr, amt_x);
        assert!(coin::balance<X>(escrow_addr) == amt_x, 0);

        // Initialize coin Y in `init_user`'s account if not already done so
        if (!coin::is_account_registered<Y>(init_user_addr)) {
            managed_coin::register<Y>(init_user);
        };

        // Update `amt_x`
        let amt_x = &mut borrow_global_mut<Escrow<X, Y>>(escrow_addr).amt_x;
        *amt_x = *amt_x + dep_x;
        // Update `req_y` to how much of coin Y `user` wants in return for his deposit
        let req_y = &mut borrow_global_mut<Escrow<X, Y>>(escrow_addr).req_y;
        *req_y = *req_y + amt_y;
    }

    /// After `init_user` has initiated a swap, `comp_user` (the user that completes the swap) will deposit `req_y`
    /// (requested y) amount of Y, and the function will transfer `amt_y` coin Y to `init_user` and `amt_x` coin X to
    /// `comp_user`
    public entry fun complete_swap<X, Y>(comp_user: &signer, init_user_addr: address, amt_y: u64)
    acquires Escrow, EscrowEvent {
        let comp_user_addr = signer::address_of(comp_user);
        let escrow_addr = borrow_global<EscrowEvent>(init_user_addr).escrow_addr;
        assert!(exists<Escrow<X, Y>>(escrow_addr), EESCROW_NOT_INIT);

        // Initialize coin X and coin Y in `comp_user`'s account if not already done so
        if (!coin::is_account_registered<X>(comp_user_addr)) {
            managed_coin::register<X>(comp_user);
        };
        if (!coin::is_account_registered<Y>(comp_user_addr)) {
            managed_coin::register<Y>(comp_user);
        };

        let req_y = borrow_global<Escrow<X, Y>>(escrow_addr).req_y;
        if (amt_y == req_y) {
            coin::transfer<Y>(comp_user, escrow_addr, amt_y);
        };

        let escrow = borrow_global_mut<Escrow<X, Y>>(escrow_addr);

        let coins_x = coin::extract_all<X>(&mut escrow.coin_x);
        coin::deposit<X>(comp_user_addr, coins_x);

        let coins_y = coin::extract_all<Y>(&mut escrow.coin_y);
        coin::deposit<Y>(init_user_addr, coins_y);
    }

    // =========== Tests =========== //

    #[test_only]
    struct CoinX {}

    #[test_only]
    struct CoinY {}

    #[test(init_user = @0x1, comp_user = @0x2)]
    public fun test_end_to_end(init_user: signer, comp_user: signer)  acquires Escrow, EscrowEvent {
        let init_user_addr = signer::address_of(&init_user);
        let comp_user_addr = signer::address_of(&comp_user);

        managed_coin::initialize<CoinX>(
            &init_user,
            b"CoinX",
            b"X",
            4,
            true
        );
        assert!(coin::is_coin_initialized<CoinX>(), 0);
        managed_coin::register<CoinX>(&init_user);
        managed_coin::mint<CoinX>(&init_user, init_user_addr, 100);

        managed_coin::initialize<CoinY>(
            &comp_user,
            b"CoinY",
            b"Y",
            4,
            true
        );
        assert!(coin::is_coin_initialized<CoinY>(), 0);
        managed_coin::register<CoinY>(&comp_user);
        managed_coin::mint<CoinY>(&comp_user, comp_user_addr, 100);

        init_escrow<CoinX, CoinY>(&init_user, b"seed");
        // Both users are receiving the full amounts of both coins.. need to fix this by allowing for variable
        // users in unit tests
        assert!(coin::balance<CoinX>(init_user_addr) == 100, EINCORRECT_BALANCE);
        assert!(coin::balance<CoinY>(init_user_addr) == 100, EINCORRECT_BALANCE);

        assert!(coin::balance<CoinX>(comp_user_addr) == 100, EINCORRECT_BALANCE);
        assert!(coin::balance<CoinY>(comp_user_addr) == 100, EINCORRECT_BALANCE);


        init_swap<CoinX, CoinY>(&init_user, 20, 70);
//        assert!(coin::balance<CoinY>(init_user_addr) == 30, EINCORRECT_BALANCE);
//        assert!(coin::balance<CoinY>(comp_user_addr) == 30, EINCORRECT_BALANCE);

        complete_swap<CoinX, CoinY>(&comp_user, init_user_addr, 70);

    }
}


