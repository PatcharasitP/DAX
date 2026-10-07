// ============================================================================
//  fnExtractPayment  (v1 — 2026-10-07)  —  ดึงยอดเงินรายการที่ต้องการจากข้อความ PAYMENT_INFO
//  ----------------------------------------------------------------------------
//  ข้อความต้นทาง (คอลัมน์ OLD_PAYMENT_INFO / PAYMENT_INFO) รูปแบบ (ตัวเลขในตัวอย่างเป็นค่าสมมติ):
//    "ค่าเช่า [12000.00] {1001}, ค่ามัดจำ(ค่าเช่า) [24000.00] {1002}, ค่ามัดจำ(ค่าเช่า) [1500.50] {1003}"
//    Sum → 25500.50    Concat → "24000.00, 1500.50"
//     ชื่อรายการ [จำนวนเงิน] {PAYMENT_ID}  คั่นแต่ละรายการด้วย ", "
//
//  พารามิเตอร์:
//    Info     ข้อความ PAYMENT_INFO (null หรือว่าง → คืน IfNone)
//    Keyword  ชื่อรายการที่ต้องการ เป็นข้อความหรือ list เช่น "ค่ามัดจำ" หรือ {"ค่ามัดจำ(ค่าเช่า)", "ค่ามัดจำ(ไฟฟ้า)"}
//             เทียบแบบไม่สนช่องว่าง → "ค่ามัดจำ (ค่าเช่า)" ตามตาราง LOV ตรงกับ "ค่ามัดจำ(ค่าเช่า)" ในข้อมูล
//    Mode     "Sum" (ค่าเริ่มต้น) = รวมยอดทุกรายการที่ตรง คืนเป็นตัวเลข (decimal ไม่มีเศษทศนิยมเพี้ยน)
//             "Concat"            = เอายอดมาต่อกันเป็นข้อความ เช่น "24000.00, 1500.50"
//    Options  [Match = "StartsWith" (ค่าเริ่มต้น) | "Exact" | "Contains",
//              Separator = ", "  (ใช้กับ Concat),
//              IfNone = null     (ค่าที่คืนเมื่อไม่มีรายการตรง เช่น 0)]
//
//  เลือก Match ให้ถูก (ข้อมูลจริงมีชื่อซ้อนกัน):
//    "ค่ามัดจำ" + StartsWith  → ได้ ค่ามัดจำ(ค่าเช่า), ค่ามัดจำ(ค่าบริการ), ค่ามัดจำ(ไฟฟ้า) ครบ
//    "ค่าเช่า"  + StartsWith  → ได้ ค่าเช่า และ ค่าเช่าช่วง  (ไม่โดน ค่ามัดจำ(ค่าเช่า))
//    "ค่าเช่า"  + Exact       → ได้ ค่าเช่า อย่างเดียว
//    "ค่าเช่า"  + Contains    → โดนทุกตัวที่มีคำนี้ รวม ค่ามัดจำ(ค่าเช่า), ค่าธรรมเนียม(ค่าเช่า)
//
//  วิธีใช้:
//    เพิ่มคอลัมน์ใหม่ (แนะนำ เก็บข้อความเดิมไว้ตรวจย้อน):
//      Table.AddColumn(prev, "OLD_DEPOSIT_AMOUNT", each fnExtractPayment([OLD_PAYMENT_INFO], "ค่ามัดจำ"), type number)
//    แทนที่คอลัมน์เดิม:
//      Table.TransformColumns(prev, {{"OLD_PAYMENT_INFO", each fnExtractPayment(_, "ค่ามัดจำ"), type number}})
//    ต่อกันเป็นข้อความ:
//      Table.AddColumn(prev, "OLD_DEPOSIT_LIST", each fnExtractPayment([OLD_PAYMENT_INFO], "ค่ามัดจำ", "Concat"), type text)
//
//  รายการที่ไม่มี [จำนวนเงิน] หรือเงินไม่ใช่ตัวเลข → error พร้อมข้อความ ไม่กลืนเงียบ
//  (รูปแบบข้อมูลเปลี่ยนเมื่อไหร่ต้องรู้ทันที ไม่ใช่ได้ยอดขาดโดยไม่มีใครเห็น)
// ============================================================================
(Info as nullable text, Keyword as any, optional Mode as nullable text, optional Options as nullable record) as any =>
let
    opt     = Options ?? [],
    modeVal = Text.Lower(Mode ?? "Sum"),
    matchBy = Text.Lower(Record.FieldOrDefault(opt, "Match", "StartsWith") ?? "StartsWith"),
    sep     = Record.FieldOrDefault(opt, "Separator", ", ") ?? ", ",
    ifNone  = Record.FieldOrDefault(opt, "IfNone", null),

    norm = (t as text) as text => Text.Remove(t, {" ", "#(00A0)"}),
    keys = List.Transform(if Keyword is list then Keyword else {Keyword}, each norm(Text.From(_))),

    isHit = (label as text) as logical =>
        let l = norm(label) in
        if matchBy = "startswith" then List.AnyTrue(List.Transform(keys, each Text.StartsWith(l, _)))
        else if matchBy = "exact" then List.Contains(keys, l)
        else List.AnyTrue(List.Transform(keys, each Text.Contains(l, _))),

    parseItem = (item as text) as record =>
        if not Text.Contains(item, "[") or not Text.Contains(item, "]") then
            error Error.Record("fnExtractPayment", "รายการไม่มี [จำนวนเงิน]: " & item)
        else
            [ Label  = Text.Trim(Text.BeforeDelimiter(item, "[")),
              Amount = Text.Trim(Text.BetweenDelimiters(item, "[", "]")) ],

    txt   = if Info = null then "" else Text.Trim(Info),
    items = if txt = "" then {} else List.Transform(Text.Split(txt, ", "), parseItem),
    hits  = List.Select(items, each isHit([Label])),

    toNum = (a as text) as number =>
        let r = try Decimal.From(a, "en-US") in
        if r[HasError] then error Error.Record("fnExtractPayment", "จำนวนเงินไม่ใช่ตัวเลข: [" & a & "]") else r[Value],

    result =
        if not List.Contains({"sum", "concat"}, modeVal) then
            error Error.Record("fnExtractPayment", "Mode ต้องเป็น ""Sum"" หรือ ""Concat"" ได้รับ: " & Mode)
        else if not List.Contains({"startswith", "exact", "contains"}, matchBy) then
            error Error.Record("fnExtractPayment", "Match ต้องเป็น StartsWith, Exact หรือ Contains ได้รับ: " & matchBy)
        else if List.IsEmpty(hits) then ifNone
        else if modeVal = "sum" then List.Sum(List.Transform(hits, each toNum([Amount])), Precision.Decimal)
        else Text.Combine(List.Transform(hits, each if toNum([Amount]) is number then [Amount] else ""), sep)
in
    result
