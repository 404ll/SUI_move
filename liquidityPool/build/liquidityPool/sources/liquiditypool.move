module liquiditypool::liquiditypool {
    use sui::balance;
    use sui::balance::{Balance, Supply};
    use sui::coin::{Self, Coin, into_balance};
    use sui::object::{Self, UID};
    use sui::tx_context::{TxContext, sender};
    use sui::transfer;
    use sui::math;
    use sui::transfer::public_transfer;

    /*---------错误码---------*/
    const Eamount : u64 = 0;
    const ElpInvaild : u64 = 0;

    /* -----结构体定义----------*/
    // onetime witness
    public struct LP<phantom CoinA, phantom CoinB> has drop {}

    // 定义流动性池的结构
    public struct Pool<phantom CoinA, phantom CoinB> has key {
        id: UID,
        coinA: Balance<CoinA>,
        coinB: Balance<CoinB>,
        lp_supply: Supply<LP<CoinA, CoinB>>,
    }

    // 定义分期付款权限证明-不可被转移
    public struct Paycap has key{
        id: UID,
    }

    //定义分期付款凭证
    public struct Installment has key,store{
        id: UID,
        installment_data: u64,//分期时间
        total_amount: u64,//总金额数
        paid_amount: u64//已支付数量
    }


    /*-------函数定义--------*/
    public fun create_pool<CoinA, CoinB>(coinA: Coin<CoinA>, coinB: Coin<CoinB>, ctx: &mut TxContext) {
        let coinA_amount = coin::value(&coinA);
        let coinB_amount = coin::value(&coinB);

        assert!(coinA_amount > 0 && coinB_amount > 0,Eamount);

        let coinA_balance = into_balance(coinA);
        let coinB_balance = into_balance(coinB);
        let paycap = Paycap { id: object::new(ctx) };

        //LP计算
        let lp_amount = math::sqrt(coinA_amount) * math::sqrt(coinB_amount);
        let mut lp_supply = balance::create_supply(LP<CoinA, CoinB>{});
        let lp_balance = balance::increase_supply(&mut lp_supply, lp_amount);

        // 创建池
        let pool = Pool {
            id: object::new(ctx),
            coinA: coinA_balance,
            coinB: coinB_balance,
            lp_supply,
            };

        transfer::share_object(pool);
        transfer::share_object(paycap);
        //返回lp给流动性提供者
        public_transfer(coin::from_balance(lp_balance, ctx), sender(ctx));
        }

    public fun add_liquidity<CoinA, CoinB>(
        pool: &mut Pool<CoinA, CoinB>,
        coinA: Coin<CoinA>,
        coinB: Coin<CoinB>,
        ctx: &mut TxContext
    ) {
        //添加的数量
        let coinA_amount = coin::value(&coinA);
        let coinB_amount = coin::value(&coinB);

        assert!(coinA_amount > 0 && coinB_amount > 0,Eamount);

        //计算现有数量
        let coinA_current_amount = balance::value(&pool.coinA);
        let coinB_current_amount = balance::value(&pool.coinB);

        //加入coinA和coinB
        let coin_a_balance = into_balance(coinA);
        let coin_b_balance = into_balance(coinB);
        balance::join(&mut pool.coinA, coin_a_balance);
        balance::join(&mut pool.coinB, coin_b_balance);

        let factor_coinA = coinA_current_amount / coinA_amount;
        let factor_coinB = coinB_current_amount / coinB_amount;

        //maintain
        let add_coinA : u64;
        let add_coinB : u64;

        if(factor_coinA == factor_coinB){
            add_coinA = coinA_amount;
            add_coinB = coinB_amount;
        }else if(factor_coinA > factor_coinB){
            add_coinA = coinA_current_amount / factor_coinA;
            add_coinB = coinB_amount;
            let refund_amount = coinA_amount - add_coinA;
            let refund_balance = balance::split(&mut pool.coinA,refund_amount);
            public_transfer(coin::from_balance(refund_balance,ctx),sender(ctx));
        }else {
            add_coinB = coinB_current_amount / factor_coinB;
            add_coinA = coinA_amount;
            let refund_amount = coinB_amount - add_coinB;
            let refund_balance = balance::split(&mut pool.coinB,refund_amount);
            public_transfer(coin::from_balance(refund_balance,ctx),sender(ctx));
        };

        //计算新的Lp并返回给用户
        let past_lp_amount = balance::supply_value(&pool.lp_supply);
        let current_lp_amount = math::sqrt(coinA_current_amount + add_coinA)*math::sqrt(coinB_current_amount + add_coinB);
        let add_lp_amount = current_lp_amount - past_lp_amount;

        let lp_balance = balance::increase_supply(&mut pool.lp_supply,add_lp_amount);
        public_transfer(coin::from_balance(lp_balance,ctx),sender(ctx));

    }

    public fun remove_liquidity<CoinA,CoinB>(pool: &mut Pool<CoinA,CoinB>,lp: Coin<LP<CoinA,CoinB>>,ctx: &mut TxContext){
        let lp_amount = coin::value (&lp);
        assert!(lp_amount > 0,ElpInvaild);

        //计算现有数量
        let coinA_current_amount = balance::value(&pool.coinA);
        let coinB_current_amount = balance::value(&pool.coinB);
        let lp_current_amount = balance::supply_value(&pool.lp_supply);

        //计算应得CoinA,CoinB数量
        let factor = lp_amount / lp_current_amount;
        let remove_coinA_amount =  factor * coinA_current_amount;
        let remove_coinB_amount =  factor * coinB_current_amount;
        let remove_coinA_balance  = balance::split(&mut pool.coinA,remove_coinA_amount);
        let remove_coinB_balance  = balance::split(&mut pool.coinB,remove_coinB_amount);

        //减少LP
        balance::decrease_supply(&mut pool.lp_supply,coin::into_balance(lp));
        //将代币转移给用户
        public_transfer(coin::from_balance(remove_coinA_balance,ctx),sender(ctx));
        public_transfer(coin::from_balance(remove_coinB_balance,ctx),sender(ctx));
    }


    public fun swap_A_to_B<CoinA,CoinB>(pool:&mut Pool<CoinA,CoinB>,in: Coin<CoinA>,ctx:&mut TxContext){
        let in_amount = coin::value(&in);
        let coinA_amount = balance::value(&pool.coinA);
        let coinB_amount = balance::value(&pool.coinB);

        assert!(in_amount > 0 ,Eamount);
        //计算swap后剩余的数量
        let new_coinB_amount = coinA_amount * coinB_amount / (coinA_amount + in_amount);
        let swap_coinB_amount = (coinB_amount - new_coinB_amount);
        let swap_coinB_balance = balance::split(&mut pool.coinB, swap_coinB_amount);

        balance::join(&mut pool.coinA,coin::into_balance(in));
        public_transfer(coin::from_balance(swap_coinB_balance,ctx),sender(ctx));
        
    }

    public fun swap_B_to_A<CoinA,CoinB>(pool:&mut Pool<CoinA,CoinB>,in: Coin<CoinB>,ctx:&mut TxContext){

        let in_amount = coin::value(&in);
        let coinA_amount = balance::value(&pool.coinA);
        let coinB_amount = balance::value(&pool.coinB);

        assert!(in_amount > 0 ,Eamount);
        //计算swap后剩余的数量
        let new_coinA_amount = coinB_amount * coinA_amount / (coinB_amount + in_amount);
        let swap_coinA_amount = (coinA_amount - new_coinA_amount);
        let swap_coinA_balance = balance::split(&mut pool.coinA, swap_coinA_amount);

        balance::join(&mut pool.coinB,coin::into_balance(in));
        public_transfer(coin::from_balance(swap_coinA_balance,ctx),sender(ctx));
    }



    /*--------查询--------*/
    //查询pool中的数据
    public fun pool_balances<A, B>(pool: &Pool<A, B>): (u64, u64, u64) {
        (
            balance::value(&pool.coinA),
            balance::value(&pool.coinB),
            balance::supply_value(&pool.lp_supply)
        )
    }


}
