module  liquiditypool::liquiditypool {
    use sui::balance;
    use sui::balance::{Balance, Supply};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin, into_balance};
    use sui::object::{Self, UID};
    use sui::tx_context::{TxContext, sender};
    use sui::transfer;
    use sui::math;
    use sui::transfer::public_transfer;

    /*---------Error Codes---------*/
    const Eamount : u64 = 0; // Invalid amount error code
    const ElpInvaild : u64 = 0; // Invalid LP error code

    /*---------Enum Types----------*/
    enum CurrentStatus {
        Pending,   // Pending payment
        Paid,      // Paid
        Overdue,   // Overdue
    }

    /*----------Operation Codes----------*/
    /*
    1: Paid the current bill
    2: Unpaid current bill, marked as overdue
    */

    /* -----Structure Definitions----------*/
    // One-time witness
    public struct LP<phantom CoinA, phantom CoinB> has drop {}

    // Define liquidity pool structure
    public struct Pool<phantom CoinA, phantom CoinB> has key {
        id: UID, // Unique identifier for the pool
        coinA: Balance<CoinA>, // Balance of CoinA
        coinB: Balance<CoinB>, // Balance of CoinB
        lp_supply: Supply<LP<CoinA, CoinB>>, // Liquidity provider supply
    }

    // Define installment payment permission proof - non-transferable
        public struct Paycap has key {
        id: UID, // Unique identifier for the payment cap
    }

    // Define installment payment voucher
        public struct Installment has key {
        id: UID, // Unique identifier for the installment
        data: u64, // Timestamp or other metadata
        installment_data: u64, // Number of installments
        total_amount: u64, // Total amount to be paid
        paid_data: u64, // Amount paid so far
        status: bool, // Current status: true for active, false for completed or canceled
    }

    // Each installment payment data
        public struct InstallmentData has store, drop {
        current_status: CurrentStatus, // Current payment status (Pending, Paid, Overdue)
        timestamp: u64, // Timestamp of the installment data
        current_paid: u64 // Amount paid for this installment
    }

    /*-------Function Definitions--------*/

    // Create liquidity pool
    public fun create_pool<CoinA, CoinB>(coinA: Coin<CoinA>, coinB: Coin<CoinB>, ctx: &mut TxContext) {
        let coinA_amount = coin::value(&coinA);
        let coinB_amount = coin::value(&coinB);

        assert!(coinA_amount > 0 && coinB_amount > 0, Eamount);

        let coinA_balance = into_balance(coinA);
        let coinB_balance = into_balance(coinB);
        let paycap = Paycap { id: object::new(ctx) };

        // Calculate LP
        let lp_amount = math::sqrt(coinA_amount) * math::sqrt(coinB_amount);
        let mut lp_supply = balance::create_supply(LP<CoinA, CoinB>{});
        let lp_balance = balance::increase_supply(&mut lp_supply, lp_amount);

        // Create pool
        let pool = Pool {
            id: object::new(ctx),
            coinA: coinA_balance,
            coinB: coinB_balance,
            lp_supply,
        };

        transfer::share_object(pool);
        transfer::share_object(paycap);

        // Return LP to liquidity providers
        public_transfer(coin::from_balance(lp_balance, ctx), sender(ctx));
    }

    // Add liquidity to pool
    public fun add_liquidity<CoinA, CoinB>(
        pool: &mut Pool<CoinA, CoinB>,
        coinA: Coin<CoinA>,
        coinB: Coin<CoinB>,
        ctx: &mut TxContext
        ) {
        // Amounts being added
        let coinA_amount = coin::value(&coinA);
        let coinB_amount = coin::value(&coinB);

        assert!(coinA_amount > 0 && coinB_amount > 0, Eamount);

        // Current pool balances
        let coinA_current_amount = balance::value(&pool.coinA);
        let coinB_current_amount = balance::value(&pool.coinB);

        // Add coinA and coinB
        let coin_a_balance = into_balance(coinA);
        let coin_b_balance = into_balance(coinB);
        balance::join(&mut pool.coinA, coin_a_balance);
        balance::join(&mut pool.coinB, coin_b_balance);

        // Calculate the added ratio
        let factor_coinA = coinA_current_amount / coinA_amount;
        let factor_coinB = coinB_current_amount / coinB_amount;

        // Maintain ratio, refund extra
        let add_coinA: u64;
        let add_coinB: u64;

        if (factor_coinA == factor_coinB) {
            add_coinA = coinA_amount;
            add_coinB = coinB_amount;
        } else if (factor_coinA > factor_coinB) {

            add_coinA = coinA_current_amount / factor_coinA;
            add_coinB = coinB_amount;
            let refund_amount = coinA_amount - add_coinA;
            let refund_balance = balance::split(&mut pool.coinA, refund_amount);

            public_transfer(coin::from_balance(refund_balance, ctx), sender(ctx));

        } else {
            add_coinB = coinB_current_amount / factor_coinB;
            add_coinA = coinA_amount;
            let refund_amount = coinB_amount - add_coinB;
            let refund_balance = balance::split(&mut pool.coinB, refund_amount);
            public_transfer(coin::from_balance(refund_balance, ctx), sender(ctx));
        };

        // Calculate new LP and return to user
        let past_lp_amount = balance::supply_value(&pool.lp_supply);
        let current_lp_amount = math::sqrt(coinA_current_amount + add_coinA) * math::sqrt(coinB_current_amount + add_coinB);
        let add_lp_amount = current_lp_amount - past_lp_amount;

        let lp_balance = balance::increase_supply(&mut pool.lp_supply, add_lp_amount);
        public_transfer(coin::from_balance(lp_balance, ctx), sender(ctx));
    }

    // Remove liquidity from pool
    public fun remove_liquidity<CoinA, CoinB>(pool: &mut Pool<CoinA, CoinB>, lp: Coin<LP<CoinA, CoinB>>, ctx: &mut TxContext) {
        let lp_amount = coin::value(&lp);
        assert!(lp_amount > 0, ElpInvaild);

        // Current pool balances
        let coinA_current_amount = balance::value(&pool.coinA);
        let coinB_current_amount = balance::value(&pool.coinB);
        let lp_current_amount = balance::supply_value(&pool.lp_supply);

        // Calculate amount of CoinA and CoinB to remove
        let factor = lp_amount / lp_current_amount;
        let remove_coinA_amount = factor * coinA_current_amount;
        let remove_coinB_amount = factor * coinB_current_amount;
        let remove_coinA_balance = balance::split(&mut pool.coinA, remove_coinA_amount);
        let remove_coinB_balance = balance::split(&mut pool.coinB, remove_coinB_amount);

        // Decrease LP
        balance::decrease_supply(&mut pool.lp_supply, coin::into_balance(lp));

        // Transfer tokens to user
        public_transfer(coin::from_balance(remove_coinA_balance, ctx), sender(ctx));
        public_transfer(coin::from_balance(remove_coinB_balance, ctx), sender(ctx));
    }

    // Swap CoinA for CoinB
    public fun swap_A_to_B<CoinA, CoinB>(pool: &mut Pool<CoinA, CoinB>, in: Coin<CoinA>, ctx: &mut TxContext) {
        let in_amount = coin::value(&in);
        let coinA_amount = balance::value(&pool.coinA);
        let coinB_amount = balance::value(&pool.coinB);

        assert!(in_amount > 0, Eamount);

        // Calculate remaining CoinB amount after swap
        let new_coinB_amount = coinA_amount * coinB_amount / (coinA_amount + in_amount);
        let swap_coinB_amount = (coinB_amount - new_coinB_amount);
        let swap_coinB_balance = balance::split(&mut pool.coinB, swap_coinB_amount);

        balance::join(&mut pool.coinA, coin::into_balance(in));
        public_transfer(coin::from_balance(swap_coinB_balance, ctx), sender(ctx));
    }

    // Swap CoinB for CoinA
    public fun swap_B_to_A<CoinA, CoinB>(pool: &mut Pool<CoinA, CoinB>, in: Coin<CoinB>, ctx: &mut TxContext) {
        let in_amount = coin::value(&in);
        let coinA_amount = balance::value(&pool.coinA);
        let coinB_amount = balance::value(&pool.coinB);

        assert!(in_amount > 0, Eamount);

        // Calculate remaining CoinA amount after swap
        let new_coinA_amount = coinB_amount * coinA_amount / (coinB_amount + in_amount);
        let swap_coinA_amount = (coinA_amount - new_coinA_amount);
        let swap_coinA_balance = balance::split(&mut pool.coinA, swap_coinA_amount);

        balance::join(&mut pool.coinB, coin::into_balance(in));
        public_transfer(coin::from_balance(swap_coinA_balance, ctx), sender(ctx));
    }


/*------------the logic of installment------------*/
    public fun mint_installment_NFT(_: & Paycap, data: u64, total: u64, clock:&Clock, ctx: &mut TxContext) {
        let paid_data = 0;
        let installmentNFT = Installment {
            id: object::new(ctx),
            data: clock::timestamp_ms(clock),
            installment_data: data,
            total_amount: total,
            paid_data,
            status: false,
        };
        transfer::share_object(installmentNFT);
    }
    ///?
    public fun updata_installmentData(installmentNFT:&mut Installment, currentData:&mut InstallmentData,code: u64,clock:&Clock,ctx:&mut TxContext){

        if(code == 1) {
            currentData.current_status = CurrentStatus::Paid;
            //更新总付款记录
            installmentNFT.paid_data = installmentNFT.paid_data + 1;

        };
        if(code == 2){
            currentData.current_status = CurrentStatus::Overdue;
        };

        if(installmentNFT.paid_data== installmentNFT.installment_data && currentData.current_paid == installmentNFT.total_amount){
            installmentNFT.status = true;
        }

    }

    // public fun pay(_:Paycap, currentData:&mut InstallmentData){
    //
    // }

    /*--------query--------*/
    //query the data of pool
    public fun pool_balances<A, B>(pool: &Pool<A, B>): (u64, u64, u64) {
        (
            balance::value(&pool.coinA),
            balance::value(&pool.coinB),
            balance::supply_value(&pool.lp_supply)
        )
    }
}
