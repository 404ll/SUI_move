/*
/// Module: hcsc
module hcsc::hcsc;
*/
module contract::hcsc;
use std::ascii::String;
use std::vector;
use sui::table;
use sui::object;
use sui::transfer;
use sui::tx_context;

/*--------------error-------------*/
    const ENotexist : u64 = 0;

public struct LabReport has key {
    id: UID,
    //白细胞 - White Blood Cells (WBC)
    wbc: u64,
    //红细胞 - Red Blood Cells (RBC)
    rbc: u64,
    // 血小板
    platelets: u64,
    // C反应蛋白 - C-Reactive Protein (CRP)
    crp: u64,
}

public struct UserRegistry has key {
    id: UID,
    user_reports: table::Table<address, vector<address>>
}

//未使用
public struct AdminCap has key {
    id: UID
    }

fun init(ctx: &mut TxContext) {
    transfer::transfer(
        AdminCap { id: object::new(ctx) },
        tx_context::sender(ctx)
    );

    transfer::share_object(
        UserRegistry {
            id: object::new(ctx),
            user_reports: table::new(ctx)
        }
    );
}

public entry fun create_lab_report(
    wbc: u64,
    rbc: u64,
    platelets: u64,
    crp: u64,
    user_registry: &mut UserRegistry,
    ctx: &mut TxContext
) {
    let lab_rep = LabReport {
        id: object::new(ctx),
        wbc,
        rbc,
        platelets,
        crp
    };

    //将用户记录到报告单中
    if (table::contains(&user_registry.user_reports, tx_context::sender(ctx))) {
        let mut v = table::borrow_mut(&mut user_registry.user_reports, tx_context::sender(ctx));
        vector::push_back(v, lab_rep.id.to_address());
    }else {
        let vec: vector<address> = vector[lab_rep.id.to_address()];
        table::add(&mut user_registry.user_reports, tx_context::sender(ctx), vec);
    };


    transfer::transfer(
        lab_rep,
        tx_context::sender(ctx)
    );
}

public entry fun get_user_reports(user_registry: &UserRegistry, user: address,ctx: &mut TxContext): vector<address> {
    assert!(table::contains(&user_registry.user_reports, user),ENotexist);
    let reports = table::borrow(&user_registry.user_reports, user);
    *reports
}

