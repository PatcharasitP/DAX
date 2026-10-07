// ============================================================================
//  fnDepositLatest  (v1 — 2026-10-07)  —  หาเงินมัดจำตัวล่าสุดของแต่ละลูกโซ่ แล้วรวมตามสัญญาปลายทาง
//  ----------------------------------------------------------------------------
//  ปัญหาที่แก้:
//    เงินมัดจำต่อกันเป็นลูกโซ่ ตัวใหม่ชี้กลับหาตัวเก่าทาง FROM_DEPOSIT_ID และทุกตัวยังติดสัญญาต้นทาง
//    (CONTRACT_CODE) เดิม สัญญาที่เงินถูกย้ายไปอยู่ใน NEW_CONTRACT_CODE ของตัวใดตัวหนึ่งในลูกโซ่
//    การกรองสถานะก่อนแล้ว Table.Distinct ตาม "NEW ถ้าว่างใช้ CONTRACT_CODE" ทำให้
//      1) หยิบตัวกลางลูกโซ่แทนตัวล่าสุด (Distinct เก็บแถวแรกที่ SQL ส่งมา)
//      2) ตัวล่าสุดที่ NEW ว่างได้สัญญาต้นทาง ไม่ใช่สัญญาปลายทาง
//      3) ตัวก่อนหน้าที่ถูกกรองทิ้ง (TRANSFERRED, PLACED) ทำให้ตามลูกโซ่ไม่ได้
//      4) มัดจำหลายก้อนของสัญญาเดียวกัน (ค่าเช่า ค่าบริการ) เหลือก้อนเดียว
//
//  ขั้นตอน:
//    1. ตัวล่าสุด = มัดจำที่ไม่มีแถวไหนชี้ FROM_DEPOSIT_ID กลับมาหา (ไม่ใช้ TO_DEPOSIT_ID = 0
//       เพราะข้อมูลจริงมีตัวแม่ที่ TO = 0 ทั้งที่มีตัวลูกแล้ว)
//    2. สัญญาปลายทาง = NEW_CONTRACT_CODE ของตัวล่าสุด ถ้าว่างไล่ย้อนตัวก่อนหน้าทีละตัว
//       ใช้ตัวแรกที่ไม่ว่าง ถ้าย้อนจนสุดยังว่างใช้ CONTRACT_CODE ของตัวล่าสุด
//    3. กรองสถานะเฉพาะตัวล่าสุด (KeepStatus)
//    4. รวมตามสัญญาปลายทาง: คอลัมน์เงินรวมกัน (นับ DEPOSIT_ID ละครั้ง กันแถวซ้ำจาก join)
//       คอลัมน์วันที่เอาค่าล่าสุด คอลัมน์อื่นต่อค่าไม่ซ้ำด้วย ", "
//
//  พารามิเตอร์:
//    Raw      ตารางมัดจำดิบ "ทุกสถานะ ยังไม่ตัดซ้ำ" ต้องมีคอลัมน์
//             DEPOSIT_ID, FROM_DEPOSIT_ID, NEW_CONTRACT_CODE, CONTRACT_CODE, DEPOSIT_STATUS
//    Options  [KeepStatus  = {"CARRIED-OVER", "PENDING CARRIED-OVER", "PENDING RETURNED", "RETURNED"}
//                            (null = เก็บทุกสถานะ),
//              SumColumns  = {"DEPOSIT_AMOUNT", "PENDING_RETURN_AMOUNT", "RETURN_AMOUNT",
//                             "TRANSFER_AMOUNT", "DEDUCT_AMOUNT", "REMAIN_AMOUNT"},
//              Destination = "Destination Contract Code"   (ชื่อคอลัมน์สัญญาปลายทาง),
//              Group       = true   (false = คืนทีละมัดจำตัวล่าสุด พร้อมคอลัมน์ปลายทาง ไว้ตรวจ)]
//
//  ผลลัพธ์ (Group = true) หนึ่งแถวต่อสัญญาปลายทาง:
//    Destination Contract Code, Deposit Count, Status Conflict (สถานะไม่เหมือนกันทุกก้อน)
//    แล้วตามด้วยทุกคอลัมน์ของ Raw ที่รวมแล้ว (DEPOSIT_STATUS กลายเป็นเช่น "CARRIED-OVER, RETURNED")
//
//  ตัวอย่าง (ค่าสมมติ):
//    DEPOSIT_ID 101  TRANSFERRED   CONTRACT_CODE AAA-2012  NEW AAA-2023  FROM 0
//    DEPOSIT_ID 102  CARRIED-OVER  CONTRACT_CODE AAA-2012  NEW (ว่าง)    FROM 101
//    → ตัวล่าสุดคือ 102 สัญญาปลายทาง AAA-2023 สถานะ CARRIED-OVER
//
//  วิธีใช้ใน Advanced Editor ของ query มัดจำ:
//    let
//        Source = Sql.Database("<server>", "<database>", [Query = "<SQL เดิม>"]),
//        Result = fnDepositLatest(Source)
//    in
//        Result
//
//  ‼️ ยังไม่ได้ตัดสินจากเจ้าของระบบ: ตัวแม่ถูกเปลี่ยนเป็น RETURNED หลังสร้างตัวลูกไปแล้ว
//     ฟังก์ชันนี้ยึดตามลูกโซ่ (ตัวลูกคือตัวล่าสุด) ถ้าเจ้าของระบบบอกให้ยึดตัวแม่ต้องแก้ขั้นที่ 1
// ============================================================================
(Raw as table, optional Options as nullable record) as table =>
let
    opt        = Options ?? [],
    keepStatus = Record.FieldOrDefault(opt, "KeepStatus",
                    {"CARRIED-OVER", "PENDING CARRIED-OVER", "PENDING RETURNED", "RETURNED"}),
    sumCols    = Record.FieldOrDefault(opt, "SumColumns",
                    {"DEPOSIT_AMOUNT", "PENDING_RETURN_AMOUNT", "RETURN_AMOUNT",
                     "TRANSFER_AMOUNT", "DEDUCT_AMOUNT", "REMAIN_AMOUNT"}),
    destName   = Record.FieldOrDefault(opt, "Destination", "Destination Contract Code"),
    doGroup    = Record.FieldOrDefault(opt, "Group", true),
    maxDepth   = 200,   // กันลูกโซ่วนกลับหาตัวเอง

    need    = {"DEPOSIT_ID", "FROM_DEPOSIT_ID", "NEW_CONTRACT_CODE", "CONTRACT_CODE", "DEPOSIT_STATUS"},
    missing = List.Difference(need, Table.ColumnNames(Raw)),

    key   = (v as any) as text => if v = null then "" else Text.From(v, "en-US"),
    blank = (v as any) as logical => v = null or Text.Trim(Text.From(v, "en-US")) = "",

    // ── ตารางแฮช DEPOSIT_ID → [F = FROM, N = NEW] (สร้างครั้งเดียว ไม่ไล่ list ต่อแถว) ──
    links = Table.Buffer(Table.Distinct(
                Table.SelectColumns(Raw, {"DEPOSIT_ID", "FROM_DEPOSIT_ID", "NEW_CONTRACT_CODE"}), {"DEPOSIT_ID"})),
    dict  = Record.FromList(
                List.Transform(Table.ToRecords(links), each [F = [FROM_DEPOSIT_ID], N = [NEW_CONTRACT_CODE]]),
                List.Transform(links[DEPOSIT_ID], key)),

    // ── ตัวที่มีลูกชี้กลับมา = ไม่ใช่ตัวล่าสุด ──
    parentKeys = List.Distinct(List.Select(List.Transform(Raw[FROM_DEPOSIT_ID], key), each _ <> "" and _ <> "0")),
    parents    = Record.FromList(List.Repeat({true}, List.Count(parentKeys)), parentKeys),

    destOf = (id as any) as nullable text =>
        let
            walk = List.Generate(
                () => [r = Record.FieldOrDefault(dict, key(id), null), d = 0],
                each [r] <> null and [d] < maxDepth,
                each [r = Record.FieldOrDefault(dict, key([r][F]), null), d = [d] + 1],
                each [r][N]),
            hit = List.First(List.Select(walk, each not blank(_)), null)
        in
            if hit = null then null else Text.Trim(Text.From(hit, "en-US")),

    latest   = Table.SelectRows(Raw, each not Record.HasFields(parents, key([DEPOSIT_ID]))),
    withDest = Table.AddColumn(latest, destName,
                   each let d = destOf([DEPOSIT_ID]) in if d = null then Text.From([CONTRACT_CODE], "en-US") else d,
                   type text),
    kept     = if keepStatus = null then withDest
               else Table.SelectRows(withDest, each List.Contains(keepStatus, [DEPOSIT_STATUS])),

    // ── รวมตามสัญญาปลายทาง ──
    schema    = Table.Schema(Raw),
    dateCols  = Table.SelectRows(schema, each List.Contains({"date", "datetime", "datetimezone"}, [Kind]))[Name],
    otherCols = Table.ColumnNames(Raw),
    sumHere   = List.Intersect({sumCols, otherCols}),
    joinText  = (vals as list) as nullable text =>
        let t = List.Sort(List.Distinct(List.Transform(List.Select(vals, each not blank(_)), each Text.From(_, "en-US"))))
        in if List.IsEmpty(t) then null else Text.Combine(t, ", "),

    aggregate = (t as table) as record =>
        let
            perDeposit = Table.Distinct(t, {"DEPOSIT_ID"}),
            statuses   = List.Distinct(List.Select(t[DEPOSIT_STATUS], each not blank(_))),
            values     = List.Transform(otherCols, (c) =>
                            if List.Contains(sumHere, c) then List.Sum(Table.Column(perDeposit, c))
                            else if List.Contains(dateCols, c) then List.Max(Table.Column(t, c))
                            else joinText(Table.Column(t, c)))
        in
            Record.Combine({
                [#"Deposit Count" = Table.RowCount(perDeposit), #"Status Conflict" = List.Count(statuses) > 1],
                Record.FromList(values, otherCols)}),

    grouped  = Table.Group(kept, {destName}, {{"__agg", each aggregate(_), type record}}),
    expanded = Table.ExpandRecordColumn(grouped, "__agg", {"Deposit Count", "Status Conflict"} & otherCols),
    typed    = Table.TransformColumnTypes(expanded,
                   {{"Deposit Count", Int64.Type}, {"Status Conflict", type logical}}
                   & List.Transform(sumHere, each {_, type number})
                   & List.Transform(dateCols, each {_, type datetime})
                   & List.Transform(List.Difference(otherCols, sumHere & dateCols), each {_, type text})),
    sorted   = Table.Sort(typed, {{destName, Order.Ascending}}),

    result =
        if not List.IsEmpty(missing) then
            error Error.Record("fnDepositLatest", "ตารางขาดคอลัมน์: " & Text.Combine(missing, ", "))
        else if doGroup then sorted
        else kept
in
    result
