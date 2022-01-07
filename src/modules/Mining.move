address 0xa85291039ddad8845d5097624c81c3fd {
module Mining {
    use 0x1::Token;
    use 0x1::Account;
    use 0x1::Event;
    use 0x1::Signer;
    use 0x290c7b35320a4dd26f651fd184373fe7::KIKO::{Self, KIKO};

    const PERMISSION_DENIED: u64 = 100001;
    const POOL_NOT_EXISTS: u64 = 100002;
    const STAKING_NOT_EXISTS: u64 = 100003;
    const INSUFFICIENT_BALANCE: u64 = 100004;
    const INSUFFICIENT_STAKING: u64 = 100005;

    const OWNER: address = @0xa85291039ddad8845d5097624c81c3fd;

    struct Trading has key, store {
        // event
        trading_harvest_event: Event::EventHandle<TradingHarvestEvent>,
    }

    // event emitted when harvest trading profit
    struct TradingHarvestEvent has drop, store {
        sender: address,
        // to user
        to: address,
        // amount
        amount: u128,
        // fee
        fee: u128,
    }

    // init trading
    public fun init(sender: &signer) {
        assert_manager(sender);
        if (!exists<Trading>(OWNER)) {
            move_to<Trading>(sender,
                Trading {
                    trading_harvest_event: Event::new_event_handle<TradingHarvestEvent>(sender),
            });
        };
    }

    // harvest trading profit
    public fun trading_harvest(sender: &signer, to: address, amount: u128, fee: u128) acquires Trading {
        assert_manager(sender);
        harvest(sender, to, amount, fee);
        // emit event
        if (!exists<Trading>(OWNER)) {
            move_to<Trading>(sender,
                Trading {
                    trading_harvest_event: Event::new_event_handle<TradingHarvestEvent>(sender),
                });
        };
        let trading = borrow_global_mut<Trading>(OWNER);
        Event::emit_event(
            &mut trading.trading_harvest_event,
            TradingHarvestEvent {
                sender: Signer::address_of(sender),
                to: to,
                amount: amount,
                fee: fee,
            }
        );
    }

    fun harvest(sender: &signer, to: address, amount: u128, fee: u128) {
        let tokens = KIKO::withdraw_amount_by_linear(sender, amount);
        // take gas
        if (fee >= amount) {
            Account::deposit(OWNER, tokens);
            return
        } else if (fee > 0) {
            let fee_tokens = Token::withdraw(&mut tokens, fee);
            Account::deposit(OWNER, fee_tokens);
        };
        // deposit to user
        Account::deposit(to, tokens);
    }

    fun assert_manager(sender: &signer) {
        assert(Signer::address_of(sender) == OWNER, PERMISSION_DENIED);
    }

    // ******************** LPToken stake ********************

    // stake pool
    struct LPStakePool<LP: store> has key, store {
        // lp tokens
        lp_tokens: Token::Token<LP>,
        // event
        lp_stake_event: Event::EventHandle<LPStakeEvent>,
        lp_unstake_event: Event::EventHandle<LPUnstakeEvent>,
        lp_harvest_event: Event::EventHandle<LPHarvestEvent>,
    }

    // stake info for user
    struct LPStaking<LP: store> has key, store {
        // lp tokens amount
        amount: u128,
    }

    // event emitted when stake lp token
    struct LPStakeEvent has drop, store {
        sender: address,
        // token code
        token_code: Token::TokenCode,
        // staking amount
        amount: u128,
        // record id
        record_id: u128,
    }

    // event emitted when unstake lp token
    struct LPUnstakeEvent has drop, store {
        sender: address,
        // token code
        token_code: Token::TokenCode,
        // staking amount
        amount: u128,
        // record id
        record_id: u128,
    }

    // event emitted when harvest lp stake profit
    struct LPHarvestEvent has drop, store {
        sender: address,
        // token code
        token_code: Token::TokenCode,
        // to user
        to: address,
        // amount
        amount: u128,
        // fee
        fee: u128,
    }

    public fun lp_init<LP: store>(sender: &signer) {
        assert_manager(sender);
        if (!exists<LPStakePool<LP>>(OWNER)) {
            move_to(sender,
                LPStakePool<LP> {
                    lp_tokens: Token::zero(),
                    // event
                    lp_stake_event: Event::new_event_handle<LPStakeEvent>(sender),
                    lp_unstake_event: Event::new_event_handle<LPUnstakeEvent>(sender),
                    lp_harvest_event: Event::new_event_handle<LPHarvestEvent>(sender),
                });
        };
    }

    public fun lp_stake<LP: store>(sender: &signer, amount: u128, record_id: u128) acquires LPStaking, LPStakePool {
        // pool exists
        assert(!exists<LPStakePool<LP>>(OWNER), POOL_NOT_EXISTS);
        // lp balance
        let sender_address = Signer::address_of(sender);
        let lp_balance = Account::balance<LP>(sender_address);
        assert(amount > lp_balance, INSUFFICIENT_BALANCE);
        // deposit token
        let lp_tokens = Account::withdraw<LP>(sender, amount);
        let stake_pool = borrow_global_mut<LPStakePool<LP>>(OWNER);
        Token::deposit(&mut stake_pool.lp_tokens, lp_tokens);
        // add amount
        if (!exists<LPStaking<LP>>(sender_address)) {
            move_to(sender, LPStaking<LP> {
                amount: amount,
            });
        } else {
            let staking = borrow_global_mut<LPStaking<LP>>(sender_address);
            staking.amount = staking.amount + amount;
        };
        // accept kiko
        if (!Account::is_accepts_token<KIKO>(sender_address)){
            Account::do_accept_token<KIKO>(sender);
        };
        // emit event
        Event::emit_event(
            &mut stake_pool.lp_stake_event,
            LPStakeEvent {
                sender: sender_address,
                token_code: Token::token_code<LP>(),
                amount: amount,
                record_id: record_id,
            }
        );
    }

    public fun lp_unstake<LP: store>(sender: &signer, amount: u128, record_id: u128) acquires LPStaking, LPStakePool {
        // staking amount
        let sender_address = Signer::address_of(sender);
        assert(!exists<LPStaking<LP>>(sender_address), STAKING_NOT_EXISTS);
        let staking = borrow_global_mut<LPStaking<LP>>(sender_address);
        assert(staking.amount > 0, INSUFFICIENT_STAKING);

        let withdraw_amount;
        if (staking.amount <= amount) {
            withdraw_amount = staking.amount;
        } else {
            withdraw_amount = amount;
        };
        // withdraw lp
        let stake_pool = borrow_global_mut<LPStakePool<LP>>(OWNER);
        let lp_tokens = Token::withdraw<LP>(&mut stake_pool.lp_tokens, withdraw_amount);
        Account::deposit(sender_address, lp_tokens);
        // sub amount
        staking.amount = staking.amount - withdraw_amount;
        // emit event
        Event::emit_event(
            &mut stake_pool.lp_unstake_event,
            LPUnstakeEvent {
                sender: sender_address,
                token_code: Token::token_code<LP>(),
                amount: amount,
                record_id: record_id,
            }
        );
    }

    public fun lp_harvest<LP: store>(sender: &signer, to: address, amount: u128, fee: u128) acquires LPStakePool {
        assert_manager(sender);
        harvest(sender, to, amount, fee);
        // emit event
        let stake_pool = borrow_global_mut<LPStakePool<LP>>(OWNER);
        Event::emit_event(
            &mut stake_pool.lp_harvest_event,
            LPHarvestEvent {
                sender: Signer::address_of(sender),
                token_code: Token::token_code<LP>(),
                to: to,
                amount: amount,
                fee: fee,
            }
        );
    }

}
}
