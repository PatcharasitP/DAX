// ============================================================================
//  FnDepositLatestTests — ชุดทดสอบ fnDepositLatest v1 (2026-10-07)
//  ข้อมูลสมมติจำลองทุกเคสที่เจอในข้อมูลจริง (ลูกโซ่หลายทอด, ตัวก่อนหน้า TRANSFERRED, แม่ RETURNED มีลูก,
//  มัดจำ 2 ก้อนปลายทางเดียว, สถานะขัดกัน, ตัวล่าสุดยกเลิก, แถวซ้ำจาก join, ไม่เคยย้าย, PLACED)
//  expected สร้างด้วยตัวแยกวิเคราะห์อิสระ (Python) ไม่ได้คิดในหัว
//  รัน: pq_run_tests.ps1 -TestQuery FnDepositLatestTests -Deps fnDepositLatest
// ============================================================================
let
    fx = fnDepositLatest,
    Raw = #table(
        type table [DEPOSIT_ID = Int64.Type, FROM_DEPOSIT_ID = Int64.Type, DEPOSIT_STATUS = text,
                    CONTRACT_CODE = text, NEW_CONTRACT_CODE = text, DEPOSIT_AMOUNT = number, Payment_Method = text],
        {
            {101, 0, "TRANSFERRED", "AAA-2012", "AAA-2023", 18000, "Cash"},
            {102, 101, "CARRIED-OVER", "AAA-2012", "", 18000, "Cash"},
            {201, 0, "PENDING CARRIED-OVER", "BBB-2008", "BBB-2018-C002", 1000, "Cash"},
            {202, 201, "PENDING CARRIED-OVER", "BBB-2008", "BBB-2018-C003", 1000, "Cash"},
            {203, 202, "CARRIED-OVER", "BBB-2008", "BBB-2018-C004", 1000, "Cash"},
            {204, 203, "PENDING CARRIED-OVER", "BBB-2008", "", 1000, "Cash"},
            {301, 0, "RETURNED", "CCC-2018", "CCC-2021", 25000, "Cash"},
            {302, 301, "PENDING CARRIED-OVER", "CCC-2018", "", 25000, "Cash"},
            {401, 0, "CARRIED-OVER", "DDD-2015", "DDD-2026", 1000, "Cash"},
            {402, 0, "CARRIED-OVER", "DDD-2015", "DDD-2026", 500, "BG"},
            {501, 0, "RETURNED", "EEE-2019", "EEE-2026", 700, "Cash"},
            {502, 0, "PENDING RETURNED", "EEE-2020", "EEE-2026", 300, "Cash"},
            {601, 0, "CARRIED-OVER", "FFF-2016", "FFF-2026", 900, "Cash"},
            {602, 601, "CANCELLED", "FFF-2016", "", 900, "Cash"},
            {701, 0, "RETURNED", "GGG-2017", "GGG-2026", 300, "Cash"},
            {701, 0, "RETURNED", "GGG-2017", "GGG-2026", 300, "BG"},
            {801, 0, "PENDING RETURNED", "HHH-2015", "", 4500, "Cash"},
            {901, 0, "PLACED", "JJJ-2014", "", 2000, "Cash"}
        }),
    G    = fx(Raw),
    GAll = fx(Raw, [KeepStatus = null]),
    Flat = fx(Raw, [Group = false]),
    one  = (t as table, d as text) as record =>
        let s = Table.SelectRows(t, each [Destination Contract Code] = d) in
        if Table.RowCount(s) = 1 then s{0} else error "พบ " & Text.From(Table.RowCount(s)) & " แถวสำหรับ " & d,
    show = (t as table, d as text) as text =>
        let r = try one(t, d) in
        if r[HasError] then "ERROR: " & r[Error][Message]
        else let x = r[Value] in
            "n=" & Text.From(x[Deposit Count]) & " | conflict=" & Text.From(x[Status Conflict]) & " | " & x[DEPOSIT_STATUS]
            & " | amt=" & Number.ToText(x[DEPOSIT_AMOUNT], "0.00", "en-US") & " | pay=" & (x[Payment_Method] ?? "<null>")
            & " | ids=" & x[DEPOSIT_ID],
    e = (f as function) as text => let r = try f() in if r[HasError] then "ERROR" else "no error",
    kind = (t as table, c as text) as text => Table.SelectRows(Table.Schema(t), each [Name] = c){0}[Kind],

    cases = {
        {"ปลายทาง AAA-2023", show(G, "AAA-2023"), "n=1 | conflict=false | CARRIED-OVER | amt=18000.00 | pay=Cash | ids=102"},
        {"ปลายทาง BBB-2018-C004", show(G, "BBB-2018-C004"), "n=1 | conflict=false | PENDING CARRIED-OVER | amt=1000.00 | pay=Cash | ids=204"},
        {"ปลายทาง CCC-2021", show(G, "CCC-2021"), "n=1 | conflict=false | PENDING CARRIED-OVER | amt=25000.00 | pay=Cash | ids=302"},
        {"ปลายทาง DDD-2026", show(G, "DDD-2026"), "n=2 | conflict=false | CARRIED-OVER | amt=1500.00 | pay=BG, Cash | ids=401, 402"},
        {"ปลายทาง EEE-2026", show(G, "EEE-2026"), "n=2 | conflict=true | PENDING RETURNED, RETURNED | amt=1000.00 | pay=Cash | ids=501, 502"},
        {"ปลายทาง GGG-2026", show(G, "GGG-2026"), "n=1 | conflict=false | RETURNED | amt=300.00 | pay=BG, Cash | ids=701"},
        {"ปลายทาง HHH-2015", show(G, "HHH-2015"), "n=1 | conflict=false | PENDING RETURNED | amt=4500.00 | pay=Cash | ids=801"},
        {"ประชากร จำนวนปลายทาง (KeepStatus ค่าเริ่มต้น)", Text.From(Table.RowCount(G)), "7"},
        {"ตัวล่าสุดยกเลิก ไม่โผล่ (FFF-2026)", Text.From(Table.RowCount(Table.SelectRows(G, each [Destination Contract Code] = "FFF-2026"))), "0"},
        {"ตัวก่อนหน้าไม่ถูกนับ (FFF ต้นทางไม่โผล่)", Text.From(Table.RowCount(Table.SelectRows(G, each [Destination Contract Code] = "FFF-2016"))), "0"},
        {"KeepStatus = null จำนวนปลายทาง", Text.From(Table.RowCount(GAll)), "9"},
        {"KeepStatus = null ตัวยกเลิกได้ปลายทางจากตัวก่อนหน้า", show(GAll, "FFF-2026"), "n=1 | conflict=false | CANCELLED | amt=900.00 | pay=Cash | ids=602"},
        {"Group = false คืนทีละแถวตัวล่าสุด", Text.From(Table.RowCount(Flat)), "10"},
        {"Group = false มีคอลัมน์ปลายทาง", Text.Combine(List.Sort(List.Distinct(Flat[Destination Contract Code])), ","), "AAA-2023,BBB-2018-C004,CCC-2021,DDD-2026,EEE-2026,GGG-2026,HHH-2015"},
        {"ชนิด DEPOSIT_AMOUNT เป็น number", kind(G, "DEPOSIT_AMOUNT"), "number"},
        {"ชนิด Status Conflict เป็น logical", kind(G, "Status Conflict"), "logical"},
        {"ชนิด Deposit Count เป็น number", kind(G, "Deposit Count"), "number"},
        {"ขาดคอลัมน์ FROM_DEPOSIT_ID ต้อง error", e(() => Table.RowCount(fx(Table.RemoveColumns(Raw, {"FROM_DEPOSIT_ID"})))), "ERROR"},
        {"ลูกโซ่วนกลับหาตัวเองไม่ค้าง อ่านค่าปลายทางจริง", Text.Combine(fx(#table({"DEPOSIT_ID","FROM_DEPOSIT_ID","DEPOSIT_STATUS","CONTRACT_CODE","NEW_CONTRACT_CODE"}, {{1, 2, "RETURNED", "X", ""}, {2, 1, "RETURNED", "X", ""}, {3, 2, "RETURNED", "X", ""}}), [KeepStatus = null, Group = false])[Destination Contract Code], ","), "X"}
    },
    t = Table.FromRows(
            List.Transform(cases, each {_{0}, _{1}, _{2}, if _{1} = _{2} then "PASS" else "FAIL"}),
            {"Case", "Actual", "Expected", "Verdict"})
in
    t
