// ============================================================================
//  Deposit_Report + SAR_Report ฉบับแก้ (2026-10-07) — วางใน Advanced Editor
//  ใช้คู่กับฟังก์ชัน fnDepositLatest.pq (สร้าง Blank Query ชื่อ fnDepositLatest แล้ววางโค้ดฟังก์ชันก่อน)
//  บรรทัด Source ใช้ของเดิมในไฟล์ (ที่นี่เว้นไว้เป็น <server> <database> <SQL> เพราะ repo นี้สาธารณะ)
//
//  เปลี่ยนอะไร:
//    Deposit_Report  เดิม: เพิ่ม Fallback Contract Code → กรองสถานะ → Table.Distinct ตาม Fallback
//                    ใหม่: ดึงทุกสถานะ แล้ว fnDepositLatest หาตัวล่าสุดของลูกโซ่ + รวมตามสัญญาปลายทาง
//    SAR_Report      merge OLD_CONTRACT_CODE กับ "Destination Contract Code" แทน "Fallback Contract Code"
//                    expand เพิ่ม Destination Contract Code, Deposit Count, Status Conflict
// ============================================================================

// ─────────────── query: Deposit_Report ───────────────
let
    Source = Sql.Database("<server>", "<database>", [Query = "<SQL เดิมของ Deposit_Report ไม่ต้องแก้>"]),
    // ดึงทุกสถานะ ยังไม่ตัดซ้ำ แล้วให้ fnDepositLatest หาตัวล่าสุดของลูกโซ่ และรวมตามสัญญาปลายทาง
    Latest = fnDepositLatest(Source)
in
    Latest

// ─────────────── query: SAR_Report ───────────────
let
    Source = Sql.Database("<server>", "<database>", [Query = "<SQL เดิมของ SAR_Report ไม่ต้องแก้>"]),
    #"OLD_ENDDATE_2025-2027" = Table.SelectRows(Source, each [OLD_CONTRACT_END_DATE] >= #datetime(2025, 1, 1, 0, 0, 0) and [OLD_CONTRACT_END_DATE] <= #datetime(2027, 12, 31, 0, 0, 0)),
    Landlord_Name = Table.AddColumn(#"OLD_ENDDATE_2025-2027", "Landlord_Name", each Text.Replace([OLD_LANDLOAD_NAME], " ", ""), type text),
    #"Merged Queries" = Table.NestedJoin(Landlord_Name, {"Landlord_Name"}, Key_Account, {"Landlord_Name"}, "Key_Account", JoinKind.LeftOuter),
    #"Expanded Key_Account" = Table.ExpandTableColumn(#"Merged Queries", "Key_Account", {"รหัสสถานี", "ชื่อผู้ให้เช่า", "Group Type", "Group BU", "BU", "Group subset", "Key Account", "Key Account_Tier 4", "Key Account__Tier 3", "Key Account__Tier 2", "Key Account__Tier 1", "Landlord_Name"}, {"รหัสสถานี", "ชื่อผู้ให้เช่า", "Group Type", "Group BU", "BU", "Group subset", "Key Account", "Key Account_Tier 4", "Key Account__Tier 3", "Key Account__Tier 2", "Key Account__Tier 1", "Landlord_Name.1"}),
    #"Filtered Rows" = Table.SelectRows(#"Expanded Key_Account", each ([Landlord_Name.1] <> null)),
    #"Merged Queries1" = Table.NestedJoin(#"Filtered Rows", {"OLD_CONTRACT_CODE"}, Deposit_Report, {"Destination Contract Code"}, "Deposit_Report", JoinKind.LeftOuter),
    #"Expanded Deposit_Report" = Table.ExpandTableColumn(#"Merged Queries1", "Deposit_Report", {"Destination Contract Code", "Deposit Count", "Status Conflict", "PAYMENT_ID", "DEPOSIT_ID", "SUPPLIER_SITE_ID", "SUPPLIER_SITE_NAME", "DEPOSIT_AMOUNT", "PENDING_RETURN_AMOUNT", "RETURN_AMOUNT", "TRANSFER_AMOUNT", "DEDUCT_AMOUNT", "REMAIN_AMOUNT", "FROM_DEPOSIT_ID", "TO_DEPOSIT_ID", "CREATE_DATE", "CREATE_BY", "UPDATE_DATE", "UPDATE_BY", "DEPOSIT_STATUS", "CONTRACT_CODE", "CONTRACT_STATUS", "NEW_CONTRACT_ID", "NEW_CONTRACT_CODE", "NEW_CONTRACT_STATUS", "CONTRACT_EFFECTIVE_DATE", "CONTRACT_EXPIRY_DATE", "SITE_STATUS", "LANDLORD", "COMPANY", "SITE_TYPE", "Payment_Method"}, {"Destination Contract Code", "Deposit Count", "Status Conflict", "PAYMENT_ID", "DEPOSIT_ID", "SUPPLIER_SITE_ID", "SUPPLIER_SITE_NAME", "DEPOSIT_AMOUNT", "PENDING_RETURN_AMOUNT", "RETURN_AMOUNT", "TRANSFER_AMOUNT", "DEDUCT_AMOUNT", "REMAIN_AMOUNT", "FROM_DEPOSIT_ID", "TO_DEPOSIT_ID", "CREATE_DATE", "CREATE_BY", "UPDATE_DATE", "UPDATE_BY", "DEPOSIT_STATUS", "CONTRACT_CODE.1", "CONTRACT_STATUS", "NEW_CONTRACT_ID", "NEW_CONTRACT_CODE", "NEW_CONTRACT_STATUS.1", "CONTRACT_EFFECTIVE_DATE", "CONTRACT_EXPIRY_DATE", "SITE_STATUS", "LANDLORD", "COMPANY", "SITE_TYPE.1", "Payment_Method"}),
    #"Filtered Rows1" = Table.SelectRows(#"Expanded Deposit_Report", each [Destination Contract Code] <> null)
in
    #"Filtered Rows1"
