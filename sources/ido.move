module ido::ido {
    use sui::balance::{Self, Balance, Supply};
    use sui::coin::{Self, Coin, into_balance, from_balance};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext, sender};

    const ENotManage: u64 = 1;
    const EPriceNotZero: u64 = 2;
    const ENotStart: u64 = 3;
    const EStatus: u64 = 4;
    const EGtZero: u64 = 5;

    struct VeCoin<phantom SaleCoin, phantom RaiseCoin> has drop {}

    struct ManageCapability<phantom SaleCoin, phantom RaiseCoin> has key, store {
        id: UID,
        ido_id: ID
    }

    struct IDO<phantom SaleCoin, phantom RaiseCoin> has key {
        id: UID,
        /// real price = price / base_price
        status: u8,
        price: u64,
        base_price: u64,
        sale: Balance<SaleCoin>,
        raise: Balance<RaiseCoin>,
        ve_coin: Supply<VeCoin<SaleCoin, RaiseCoin>>,
        start_time: u64,
        end_time: u64,
        start_claim: u64,
        end_claim: u64
    }

    public entry fun create_ido<SaleCoin, RaiseCoin>(price: u64, base_price: u64, after_epoch: u64, ctx: &mut TxContext) {
        assert!(price > 0 && base_price > 0, EPriceNotZero);
        let now = tx_context::epoch(ctx);

        assert!(after_epoch > 0, EGtZero);

        let ido = IDO<SaleCoin, RaiseCoin> {
            id: object::new(ctx),
            status: 0,
            price,
            base_price,
            sale: balance::zero(),
            raise: balance::zero(),
            ve_coin: balance::create_supply(VeCoin<SaleCoin, RaiseCoin> {}),
            start_time: now + after_epoch,
            end_time: now + after_epoch + 7,
            start_claim: now + after_epoch + 8,
            end_claim: now + after_epoch + 10,
        };

        let cap = ManageCapability<SaleCoin, RaiseCoin> {
            id: object::new(ctx),
            ido_id: object::id(&ido),
        };
        transfer::transfer(cap, sender(ctx));
        transfer::share_object(ido);
    }

    public entry fun set_price<SaleCoin, RaiseCoin>(
        ido: &mut IDO<SaleCoin, RaiseCoin>,
        manage_cap: &ManageCapability<SaleCoin, RaiseCoin>,
        price: u64, base_price: u64,
        ctx: &mut TxContext) {
        assert!(price > 0 && base_price > 0, EPriceNotZero);
        let ido_id = object::id(ido);
        assert!(manage_cap.ido_id == ido_id, ENotManage);

        let now = tx_context::epoch(ctx);
        assert!(now < ido.start_time, ENotStart);

        ido.price = price;
        ido.base_price = base_price;
    }

    public entry fun withdraw_raise<SaleCoin, RaiseCoin>(
        ido: &mut IDO<SaleCoin, RaiseCoin>,
        manage_cap: &ManageCapability<SaleCoin, RaiseCoin>,
        ctx: &mut TxContext) {
        let ido_id = object::id(ido);
        assert!(manage_cap.ido_id == ido_id, ENotManage);

        let now = tx_context::epoch(ctx);
        assert!(now > ido.end_claim, ENotStart);

        let raise_value = balance::value(&ido.sale);
        let raise_balance = balance::split(&mut ido.sale, raise_value);
        let raise = from_balance(raise_balance, ctx);
        transfer::transfer(raise, sender(ctx));
    }


    public fun deposit_sale<SaleCoin, RaiseCoin>(ido: &mut IDO<SaleCoin, RaiseCoin>,
                                                 manage_cap: &ManageCapability<SaleCoin, RaiseCoin>,
                                                 in: Coin<SaleCoin>,
                                                 ctx: &mut TxContext)
    {
        let now = tx_context::epoch(ctx);
        assert!(now < ido.start_time, ENotStart);
        ido.status = 1;

        let ido_id = object::id(ido);
        assert!(manage_cap.ido_id == ido_id, ENotManage);
        coin::put(&mut ido.sale, in);
    }

    public entry fun withdraw_sale<SaleCoin, RaiseCoin>(
        ido: &mut IDO<SaleCoin, RaiseCoin>,
        manage_cap: &ManageCapability<SaleCoin, RaiseCoin>,
        ctx: &mut TxContext) {
        let now = tx_context::epoch(ctx);
        assert!(now < ido.start_time && now > ido.end_claim, ENotStart);

        ido.status = 2;

        let ido_id = object::id(ido);
        assert!(manage_cap.ido_id == ido_id, ENotManage);
        let sale_value = balance::value(&ido.sale);
        let sale_balance = balance::split(&mut ido.sale, sale_value);
        let sale = from_balance(sale_balance, ctx);
        transfer::transfer(sale, sender(ctx));
    }


    public fun claim<SaleCoin, RaiseCoin>(
        ido: &mut IDO<SaleCoin, RaiseCoin>,
        ve_coin: Coin<VeCoin<SaleCoin, RaiseCoin>>,
        ctx: &mut TxContext)
    : Coin<SaleCoin> {
        let now = tx_context::epoch(ctx);
        assert!(now >= ido.start_claim, ENotStart);
        let ve_value = coin::value(&ve_coin);
        balance::decrease_supply(&mut ido.ve_coin, into_balance(ve_coin));
        coin::take(&mut ido.sale, ve_value, ctx)
    }

    public fun purchase<SaleCoin, RaiseCoin>(
        ido: &mut IDO<SaleCoin, RaiseCoin>,
        in: Coin<RaiseCoin>,
        amount: u64,
        ctx: &mut TxContext)
    : (Coin<VeCoin<SaleCoin, RaiseCoin>>, Coin<RaiseCoin>)
    {
        let now = tx_context::epoch(ctx);
        assert!(now >= ido.start_time, ENotStart);
        assert!(ido.status == 1, EStatus);

        let need_in = (amount as u128) * (ido.price as u128) / (ido.base_price as u128);
        let coin_in = coin::split(&mut in, (need_in as u64), ctx);
        balance::join(&mut ido.raise, into_balance(coin_in));
        let ve_balance = balance::increase_supply(&mut ido.ve_coin, amount);
        (coin::from_balance(ve_balance, ctx), in)
    }
}
