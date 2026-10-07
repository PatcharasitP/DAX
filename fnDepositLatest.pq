// ============================================================================
//  fnDepositLatest  (v2 — 2026-10-07)  —  คลีนตารางมัดจำให้เชื่อมกับ SAR (Renew) ด้วย OLD_CONTRACT_CODE ได้ถูก
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
//    2. ไล่ย้อนลูกโซ่จากตัวล่าสุดถึงตัวแรก
//         สัญญาปลายทาง = NEW_CONTRACT_CODE ตัวแรกที่ไม่ว่าง (นับจากตัวล่าสุด) ถ้าไม่มีเลยใช้ CONTRACT_CODE
//         สัญญาที่ลูกโซ่ผ่าน = CONTRACT_CODE และ NEW_CONTRACT_CODE ทุกตัวในลูกโซ่
//    3. กรองสถานะเฉพาะตัวล่าสุด (KeepStatus)
//    4. แตกหนึ่งแถวต่อ "สัญญาที่ลูกโซ่ผ่าน" แล้วรวมเป็นหนึ่งแถวต่อสัญญา (Match Contract Code)
//       คอลัมน์เงินรวมกัน (นับ DEPOSIT_ID ละครั้ง กันแถวซ้ำจาก join) วันที่เอาค่าล่าสุด
//       คอลัมน์อื่นต่อค่าไม่ซ้ำด้วย ", "
//    ผลคือสัญญาเก่าในงาน Renew จับเจอมัดจำเสมอ แม้เงินย้ายไปสัญญาใหม่แล้ว และไม่แตกแถว SAR
//
//  พารามิเตอร์:
//    Raw      ตารางมัดจำดิบ "ทุกสถานะ ยังไม่ตัดซ้ำ" ต้องมีคอลัมน์
//             DEPOSIT_ID, FROM_DEPOSIT_ID, NEW_CONTRACT_CODE, CONTRACT_CODE, DEPOSIT_STATUS
//    Options  [KeepStatus  = {"CARRIED-OVER", "PENDING CARRIED-OVER", "PENDING RETURNED", "RETURNED"}
//                            (null = เก็บทุกสถานะ),
//              SumColumns  = {"DEPOSIT_AMOUNT", "PENDING_RETURN_AMOUNT", "RETURN_AMOUNT",
//                             "TRANSFER_AMOUNT", "DEDUCT_AMOUNT", "REMAIN_AMOUNT"},
//              Group       = true   (false = คืนทีละมัดจำตัวล่าสุด ไว้ตรวจ)]
//
//  ผลลัพธ์ (Group = true) หนึ่งแถวต่อสัญญาที่ลูกโซ่ผ่าน:
//    Match Contract Code        ใช้เชื่อมกับ SAR_Report[OLD_CONTRACT_CODE]
//    Destination Contract Code  เงินอยู่ที่สัญญาไหนตอนนี้ (หลายก้อนต่อด้วย ", ")
//    Deposit Count              จำนวนมัดจำตัวล่าสุดที่เกี่ยวกับสัญญานี้
//    Status Conflict            true เมื่อสถานะล่าสุดของแต่ละก้อนไม่เหมือนกัน
//    แล้วตามด้วยทุกคอลัมน์ของ Raw ที่รวมแล้ว (DEPOSIT_STATUS เป็นสถานะของตัวล่าสุด)
//  ผลลัพธ์ (Group = false) หนึ่งแถวต่อมัดจำตัวล่าสุด + Destination Contract Code + Contracts In Chain
//
//  ตัวอย่าง (ค่าสมมติ):
//    DEPOSIT_ID 101  TRANSFERRED   CONTRACT_CODE AAA-2012  NEW AAA-2023  FROM 0
//    DEPOSIT_ID 102  CARRIED-OVER  CONTRACT_CODE AAA-2012  NEW (ว่าง)    FROM 101
//    → ตัวล่าสุดคือ 102 สัญญาปลายทาง AAA-2023 สถานะ CARRIED-OVER
//    → ได้ 2 แถว: Match AAA-2012 และ Match AAA-2023 ทั้งคู่ชี้ปลายทาง AAA-2023
//      งาน Renew ที่สัญญาเก่าเป็น AAA-2012 หรือ AAA-2023 ก็จับเจอ
//
//  วิธีใช้ใน Advanced Editor:
//    Deposit_Report:  let Source = Sql.Database(...SQL เดิม...), Result = fnDepositLatest(Source) in Result
//    SAR_Report:      Table.NestedJoin(..., {"OLD_CONTRACT_CODE"}, Deposit_Report, {"Match Contract Code"}, ...)
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
    doGroup    = Record.FieldOrDefault(opt, "Group", true),
    keyName    = "Match Contract Code",
    destName   = "Destination Contract Code",
    chainName  = "Contracts In Chain",
    maxDepth   = 200,   // กันลูกโซ่วนกลับหาตัวเอง

    need    = {"DEPOSIT_ID", "FROM_DEPOSIT_ID", "NEW_CONTRACT_CODE", "CONTRACT_CODE", "DEPOSIT_STATUS"},
    missing = List.Difference(need, Table.ColumnNames(Raw)),

    key   = (v as any) as text => if v = null then "" else Text.From(v, "en-US"),
    blank = (v as any) as logical => v = null or Text.Trim(Text.From(v, "en-US")) = "",
    clean = (v as any) as text => Text.Trim(Text.From(v, "en-US")),

    // ── ตารางแฮช DEPOSIT_ID → [F = FROM, N = NEW, C = CONTRACT_CODE] (สร้างครั้งเดียว ไม่ไล่ list ต่อแถว) ──
    links = Table.Buffer(Table.Distinct(
                Table.SelectColumns(Raw, {"DEPOSIT_ID", "FROM_DEPOSIT_ID", "NEW_CONTRACT_CODE", "CONTRACT_CODE"}), {"DEPOSIT_ID"})),
    dict  = Record.FromList(
                List.Transform(Table.ToRecords(links),
                    each [F = [FROM_DEPOSIT_ID], N = [NEW_CONTRACT_CODE], C = [CONTRACT_CODE]]),
                List.Transform(links[DEPOSIT_ID], key)),

    // ── ตัวที่มีลูกชี้กลับมา = ไม่ใช่ตัวล่าสุด ──
    parentKeys = List.Distinct(List.Select(List.Transform(Raw[FROM_DEPOSIT_ID], key), each _ <> "" and _ <> "0")),
    parents    = Record.FromList(List.Repeat({true}, List.Count(parentKeys)), parentKeys),

    // ไล่ย้อนจากตัวล่าสุดถึงตัวแรก คืน [Dest, Codes]
    chainOf = (id as any, ownContract as any) as record =>
        let
            walk  = List.Generate(
                        () => [r = Record.FieldOrDefault(dict, key(id), null), d = 0],
                        each [r] <> null and [d] < maxDepth,
                        each [r = Record.FieldOrDefault(dict, key([r][F]), null), d = [d] + 1],
                        each [r]),
            news  = List.Transform(List.Select(walk, each not blank([N])), each clean([N])),
            olds  = List.Transform(List.Select(walk, each not blank([C])), each clean([C])),
            dest  = if List.IsEmpty(news) then clean(ownContract) else news{0},
            codes = List.Distinct(List.Select({clean(ownContract)} & olds & news, each _ <> ""))
        in
            [Dest = dest, Codes = codes],

    latest   = Table.SelectRows(Raw, each not Record.HasFields(parents, key([DEPOSIT_ID]))),
    kept     = if keepStatus = null then latest
               else Table.SelectRows(latest, each List.Contains(keepStatus, [DEPOSIT_STATUS])),
    withCh   = Table.AddColumn(kept, "__ch", each chainOf([DEPOSIT_ID], [CONTRACT_CODE]), type record),
    withDest = Table.AddColumn(withCh, destName, each [__ch][Dest], type text),
    withList = Table.AddColumn(withDest, chainName, each Text.Combine([__ch][Codes], ", "), type text),
    flat     = Table.RemoveColumns(withList, {"__ch"}),

    // ── แตกตามสัญญาที่ลูกโซ่ผ่าน แล้วรวมเป็นหนึ่งแถวต่อสัญญา ──
    perCode  = Table.ExpandListColumn(
                   Table.AddColumn(withDest, keyName, each [__ch][Codes], type list), keyName),
    rawCols  = Table.ColumnNames(Raw),
    schema   = Table.Schema(Raw),
    dateCols = Table.SelectRows(schema, each List.Contains({"date", "datetime", "datetimezone"}, [Kind]))[Name],
    sumHere  = List.Intersect({sumCols, rawCols}),
    outCols  = {destName} & rawCols,
    joinText = (vals as list) as nullable text =>
        let t = List.Sort(List.Distinct(List.Transform(List.Select(vals, each not blank(_)), each Text.From(_, "en-US"))))
        in if List.IsEmpty(t) then null else Text.Combine(t, ", "),

    aggregate = (t as table) as record =>
        let
            perDeposit = Table.Distinct(t, {"DEPOSIT_ID"}),
            statuses   = List.Distinct(List.Select(t[DEPOSIT_STATUS], each not blank(_))),
            values     = List.Transform(outCols, (c) =>
                            if List.Contains(sumHere, c) then List.Sum(Table.Column(perDeposit, c))
                            else if List.Contains(dateCols, c) then List.Max(Table.Column(t, c))
                            else joinText(Table.Column(t, c)))
        in
            Record.Combine({
                [#"Deposit Count" = Table.RowCount(perDeposit), #"Status Conflict" = List.Count(statuses) > 1],
                Record.FromList(values, outCols)}),

    grouped  = Table.Group(perCode, {keyName}, {{"__agg", each aggregate(_), type record}}),
    expanded = Table.ExpandRecordColumn(grouped, "__agg", {"Deposit Count", "Status Conflict"} & outCols),
    typed    = Table.TransformColumnTypes(expanded,
                   {{keyName, type text}, {"Deposit Count", Int64.Type}, {"Status Conflict", type logical}, {destName, type text}}
                   & List.Transform(sumHere, each {_, type number})
                   & List.Transform(dateCols, each {_, type datetime})
                   & List.Transform(List.Difference(rawCols, sumHere & dateCols), each {_, type text})),
    sorted   = Table.Sort(typed, {{keyName, Order.Ascending}}),

    result =
        if not List.IsEmpty(missing) then
            error Error.Record("fnDepositLatest", "ตารางขาดคอลัมน์: " & Text.Combine(missing, ", "))
        else if doGroup then sorted
        else flat
in
    result
