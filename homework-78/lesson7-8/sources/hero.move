module game_hero::hero {
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::object::{Self, ID, UID};
    use sui::math;
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::option::{Self, Option};

    struct Hero has key, store {
        id: UID,
        hp: u64,
        mana: u64,
        level: u64,
        experience: u64,
        sword: Option<Sword>,
        armor: Option<Armor>,
        game_id: ID,
    }

    struct Sword has key, store {
        id: UID,
        magic: u64,
        strength: u64,
        game_id: ID,
    }

    struct Armor has key,store {
        id: UID,
        guard: u64,
        game_id: ID,
    }

    struct Potion has key, store {
        id: UID,
        potency: u64,
        game_id: ID,
    }

    struct Monter has key {
        id: UID,
        hp: u64,
        strength: u64,
        game_id: ID,
    }

    struct GameInfo has key {
        id: UID,
        admin: address
    }

    struct GameAdmin has key {
        id: UID,
        monter_created: u64,
        game_id: ID,
    }

    struct MonterSlainEvent has copy, drop {
        slayer_address: address,
        hero: ID,
        monter: ID,
        game_id: ID,
    }

    const MAX_HP: u64 = 100;
    const EINSUFFICIENT_FUNDS: u64 = 0;
    const MIN_SWORD_COST: u64 = 10;
    const MAX_MAGIC: u64 = 10;
    const MIN_ARMOR_COST: u64 = 10;

    const EMONTER_WON: u64 = 0;
    const EP2P_DEFEAT: u64 = 0;
    const EHERO_TIRED: u64 = 1;
    const ENOT_ADMIN: u64 = 2;
    const ENO_SWORD: u64 = 4;
    const ASSERT_ERR: u64 = 5;

    #[allow(unused_function)]
    fun init(ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let id = object::new(ctx);
        let game_id = object::uid_to_inner(&id);

        transfer::freeze_object(GameInfo {
            id,
            admin: sender,
        });

        transfer::transfer(
            GameAdmin {
                id: object::new(ctx),
                monter_created: 0,
                game_id,
            },
            sender
        )
    }

    // --- Gameplay ---
    public entry fun attack(game: &GameInfo, hero: &mut Hero, monter: Monter, ctx: &TxContext) {
        check_game_id(game, hero.game_id);
        check_game_id(game, monter.game_id);
        let Monter { id: monter_id, strength: monter_strength, hp: monter_hp, game_id: _ } = monter;
        let hero_strength = hero_strength(hero);
        let hero_defense = hero_defense(hero);
        let hero_hp = hero.hp;
        let turnCounter: u64 = 1;

        while (monter_hp > hero_strength) {
            monter_hp = monter_hp - hero_strength;
            assert!((hero_hp + hero_defense/turnCounter) >= monter_strength , EMONTER_WON);
            hero_hp = hero_hp - math::max((monter_strength - hero_defense/turnCounter), 0);
        };

        hero.hp = hero_hp;
        hero.experience = hero.experience + monter_strength;
        if (hero.experience >= hero.level*10) {
            up_level_hero(hero);
            if (option::is_some(&hero.sword)) {
                level_up_sword(option::borrow_mut(&mut hero.sword), 1)
            };
        };
    
        event::emit(MonterSlainEvent {
            slayer_address: tx_context::sender(ctx),
            hero: object::uid_to_inner(&hero.id),
            monter: object::uid_to_inner(&monter_id),
            game_id: get_game_id(game)
        });
        object::delete(monter_id);
    }

    public entry fun p2p_play(game: &GameInfo, hero1: &mut Hero, hero2: &mut Hero, ctx: &TxContext) {
        check_game_id(game, hero1.game_id);
        check_game_id(game, hero2.game_id);
        let hero1_strength = hero_strength(hero1);
        let hero1_defense = hero_defense(hero1);
        let hero1_hp = hero1.hp;
        let hero2_strength = hero_strength(hero2);
        let hero2_defense = hero_defense(hero2);
        let hero2_hp = hero2.hp;
        let turnCounter: u64 = 1;

        while (hero2_hp > 0) {
            hero2_hp = hero2_hp - math::max((hero1_strength - hero2_defense/turnCounter), 0);
            assert!((hero1_hp + hero1_defense/turnCounter) >= hero2_strength, EP2P_DEFEAT);
            hero1_hp = hero1_hp - math::max((hero2_strength - hero1_defense/turnCounter), 0);
            turnCounter = turnCounter + 1;
        };

        hero1.hp = hero1_hp;
        hero1.experience = hero1.experience + hero2_strength;
        if (hero1.experience >= hero1.level*10) {
            up_level_hero(hero1);
            if (option::is_some(&hero1.sword)) {
                level_up_sword(option::borrow_mut(&mut hero1.sword), 1)
            };
        };
    }

    public fun up_level_hero(hero: &mut Hero) {
        hero.hp = MAX_HP;
        hero.level = hero.level + 1;
        hero.experience = 0;
    }

    fun level_up_sword(sword: &mut Sword, amount: u64) {
        sword.strength = sword.strength + amount
    }

    public fun hero_strength(hero: &Hero): u64 {
        if (hero.hp == 0) {
            return 0
        };

        let sword_strength = if (option::is_some(&hero.sword)) {
            sword_strength(option::borrow(&hero.sword))
        } else {
            0
        };
        hero.hp/10 + sword_strength
    }

    public fun sword_strength(sword: &Sword): u64 {
        sword.magic + sword.strength
    }

    public fun hero_defense(hero: &Hero): u64 {
        let hero_defense = if (option::is_some(&hero.armor)) {
            armor_guard(option::borrow(&hero.armor))
        } else {
            0
        };
        hero_defense
    }

    public fun armor_guard(armor: &Armor): u64 {
        armor.guard
    }

    public fun heal(hero: &mut Hero, potion: Potion) {
        assert!(hero.game_id == potion.game_id, 403);
        let Potion { id, potency, game_id: _ } = potion;
        object::delete(id);
        let new_hp = hero.hp + potency;
        hero.hp = math::min(new_hp, MAX_HP)
    }

    public fun equip_sword(hero: &mut Hero, new_sword: Sword): Option<Sword> {
        option::swap_or_fill(&mut hero.sword, new_sword)
    }

    // --- Object creation ---
    public fun create_sword(game: &GameInfo, payment: Coin<SUI>, ctx: &mut TxContext): Sword {
        let value = coin::value(&payment);
        assert!(value >= MIN_SWORD_COST, EINSUFFICIENT_FUNDS);
        transfer::public_transfer(payment, game.admin);
        let magic = (value - MIN_SWORD_COST) / MIN_SWORD_COST;
        Sword {
            id: object::new(ctx),
            magic: math::min(magic, MAX_MAGIC),
            strength: 10,
            game_id: get_game_id(game)
        }
    }

    public fun create_armor(game: &GameInfo, payment: Coin<SUI>, ctx: &mut TxContext): Armor {
        let value = coin::value(&payment);
        assert!(value >= MIN_ARMOR_COST, EINSUFFICIENT_FUNDS);
        transfer::public_transfer(payment, game.admin);
        let magic = (value - MIN_ARMOR_COST) / MIN_ARMOR_COST;
        Armor {
            id: object::new(ctx),
            guard: 10 + math::min(magic, MAX_MAGIC),
            game_id: get_game_id(game)
        }
    }

    public fun create_hero(game: &GameInfo, sword: Sword, armor: Armor, ctx: &mut TxContext): Hero {
        check_game_id(game, sword.game_id);
        check_game_id(game, armor.game_id);
        Hero {
            id: object::new(ctx),
            hp: MAX_HP,
            mana: 50,
            level: 1,
            experience: 0,
            sword: option::some(sword),
            armor: option::some(armor),
            game_id: get_game_id(game)
        }
    }

    public entry fun acquire_hero(game: &GameInfo, payment1: Coin<SUI>, payment2: Coin<SUI>, ctx: &mut TxContext) {
        let sword = create_sword(game, payment1, ctx);
        let armor = create_armor(game, payment2, ctx);
        let hero = create_hero(game, sword, armor, ctx);
        transfer::public_transfer(hero, tx_context::sender(ctx))
    }

    public entry fun send_potion(game: &GameInfo, payment: Coin<SUI>, player: address, ctx: &mut TxContext) {
        let potency = coin::value(&payment) * 10;
        transfer::public_transfer(
            Potion { id: object::new(ctx), potency, game_id: get_game_id(game) },
            player
        );
        transfer::public_transfer(payment, game.admin)
    }

    public entry fun send_monter(game: &GameInfo, admin: &mut GameAdmin, hp: u64, strength: u64, player: address, ctx: &mut TxContext) {
        check_game_id(game, admin.game_id);
        admin.monter_created = admin.monter_created + 1;
        transfer::transfer(
            Monter { id: object::new(ctx), hp, strength, game_id: get_game_id(game) },
            player
        )
    }

    // --- Game integrity / Links checks ---
    public fun check_game_id(game: &GameInfo, id: ID) {
        assert!(get_game_id(game) == id, 403); // TODO: error code
    }

    public fun get_game_id(game: &GameInfo): ID {
        object::id(game)
    }
}
