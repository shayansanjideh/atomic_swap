/// User 0 deposits x amount of coin X into an escrow, with the expectation that if someone puts y amount of coin Y,
/// both users will recieve the opposite amount

module atomic_swap::atomic_swap {

    use aptos_framework::coin;
    use std::signer;
    use aptos_framework::account;

    struct Escrow<phantom X, phantom Y> has key {
        coin_x: coin::Coin<X>,
        coin_y: coin::Coin<Y>,
        req_y: u64
    }

    struct EscrowEvent has key {
        escrow_addr: address
    }

    /// Initialize escrow
    public entry fun init_escrow<X, Y>(init_user: &signer, seed: vector<u8>) {
        move_to(
            init_user,
            Escrow<X, Y> {
                coin_x: coin::zero<X>(),
                coin_y: coin::zero<Y>(),
                req_y: 0
            }
        );
        let (escrow_signer, _escrow_signer_cap) = account::create_resource_account(init_user, seed);
        let escrow_addr = signer::address_of(&escrow_signer);
        move_to(init_user, EscrowEvent { escrow_addr });
    }

    /// Initiate swap: immediately after initializing the escrow, the user should deposit their desired amount of coin
    /// X and specify the amount of coin Y they want in return
    public entry fun init_swap<X, Y>(init_user: &signer, amt_x: u64, amt_y: u64)
    acquires Escrow, EscrowEvent {
        let user_addr = signer::address_of(init_user);
        let escrow_addr = borrow_global<EscrowEvent>(user_addr).escrow_addr;
        assert!(exists<Escrow<X, Y>>(escrow_addr), 0);

        coin::transfer<X>(init_user, escrow_addr, amt_x);
        assert!(coin::balance<X>(escrow_addr) == amt_x, 0);

        let req_y = &mut borrow_global_mut<Escrow<X, Y>>(escrow_addr).req_y;

        // Update `req_y` to how much of coin Y `user` wants in return for his deposit
        *req_y = *req_y + amt_y;
    }

    /// After `init_user` has initiated a swap, `comp_user` (the user that completes the swap) will deposit `req_y`
    /// (requested y) amount of Y, and the function will transfer `amt_y` coin Y to `init_user` and `amt_x` coin X to
    /// `comp_user`
    public entry fun complete_swap<X, Y>(comp_user: &signer, init_user_addr: address, amt_y: u64)
    acquires Escrow, EscrowEvent {
        let comp_user_addr = signer::address_of(comp_user);
        let escrow_addr = borrow_global<EscrowEvent>(init_user_addr).escrow_addr;
        assert!(exists<Escrow<X, Y>>(escrow_addr), 0);

        let req_y = borrow_global<Escrow<X, Y>>(escrow_addr).req_y;
        if (amt_y == req_y) {
            coin::transfer<Y>(comp_user, escrow_addr, amt_y);

            coin::transfer<X>()
        }
    }

}
