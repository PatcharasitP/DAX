// fnCheckVendor v1 (09/10/2026) — เทียบผู้ขายของแถว SAP กับผู้ขายของสัญญาใน SMT ที่จับคู่ไซต์ได้
//  ใช้ต่อท้าย fnMultiSourceFallbackLookup (ต้องมี Matched_Code + Match_Source + payload Vendor Code/Name (SAP))
//  เพิ่ม 3 คอลัมน์: Check Vendor (สรุป เจอทั้งคู่/เจอแค่ VendorCode/เจอแค่ VendorName/ไม่เจอทั้งคู่)
//  + Check VendorCode · Check VendorName (รายละเอียดรายตัว) ค่าที่เป็นไปได้:
//    เจอ · ไม่เจอ · หาไซต์ไม่เจอ · ไซต์ไม่ได้มาจาก SMT · SAP ไม่มีรหัส/ชื่อ · SMT ไม่มีรหัส/ชื่อ
//  รหัส: ตัดศูนย์นำหน้า (0006037391 = 6037391) · ช่อง SMT มีหลายรหัสคั่น , ; / ได้ เจอตัวใดตัวหนึ่ง = เจอ
//  ชื่อ: ตัดคำนิติบุคคล (บริษัท จำกัด มหาชน บจก. บมจ. หจก. ...) + คำนำหน้าคน + ช่องว่าง/เครื่องหมาย
//        แล้วเทียบแบบเท่ากัน หรือขึ้นต้นด้วยกัน (SAP ตัดชื่อยาวเหลือ ~35 ตัว เช่น "...จำกั")
//  ‼️ "จํากัด" (นิคหิต+สระอา) กับ "จำกัด" (สระอำ) หน้าตาเหมือนกันแต่คนละตัวอักษร ต้องแปลงก่อนเสมอ
(T as table, optional Options as nullable record) as table =>
let
    o = [ SiteCol = "Matched_Code", SourceCol = "Match_Source", SmtSource = "Latest Contract",
          SapCodeCol = "Vendor/Customer No.", SapNameCol = "Vendor/Customer Name",
          SmtCodeCol = "Vendor Code (SAP)",   SmtNameCol = "Vendor Name (SAP)",
          OutCode = "Check VendorCode", OutName = "Check VendorName", OutAll = "Check Vendor",
          MinPrefix = 4 ]
        & (Options ?? []),

    // ---- ด่านตรวจ: ลืม payload หรือพิมพ์ชื่อผิด = error ดัง ๆ ไม่ใช่ "SMT ไม่มีรหัส" เงียบ ๆ ทั้งตาราง ----
    need    = {o[SiteCol], o[SapCodeCol], o[SapNameCol], o[SmtCodeCol], o[SmtNameCol]},
    missing = List.Difference(need, Table.ColumnNames(T)),
    _guard  = if missing <> {} then error Error.Record("fnCheckVendor",
                  "ไม่พบคอลัมน์: " & Text.Combine(missing, ", ")) else true,
    hasSrc  = List.Contains(Table.ColumnNames(T), o[SourceCol]),

    Blank = (v) as logical => v = null or Text.Trim(Text.From(v)) = "",

    Codes = (v) as list =>
        if Blank(v) then {} else
        List.Select(
            List.Transform(Text.SplitAny(Text.From(v), ",;/"), each
                let t = Text.Upper(Text.Trim(_)), s = Text.TrimStart(t, "0")
                in  if s = "" and t <> "" then "0" else s),
            each _ <> ""),

    // ยาวก่อนสั้น: "ห้างหุ้นส่วนจำกัด" ต้องถูกตัดก่อน "จำกัด" ไม่งั้นเหลือ "ห้างหุ้นส่วน"
    Junk   = {"ห้างหุ้นส่วนจำกัด", "ห้างหุ้นส่วนสามัญ", "(มหาชน)", "มหาชน", "บริษัท", "จำกัด",
              "บจก.", "บมจ.", "หจก.", "บจก", "บมจ", "หจก",
              "PUBLIC COMPANY LIMITED", "COMPANY LIMITED", "CO.,LTD.", "CO., LTD.", "CO.,LTD",
              "LIMITED", "LTD.", "PCL."},
    Titles = {"นางสาว", "น.ส.", "นาง", "นาย", "MRS.", "MR.", "MS."},
    Keep   = {"ก".."๙", "A".."Z", "0".."9"},
    NormName = (v) as text =>
        if Blank(v) then "" else
        let t0 = Text.Upper(Text.Replace(Text.From(v), "ํา", "ำ")),
            t1 = Text.Trim(List.Accumulate(Junk, t0, (s, j) => Text.Replace(s, j, " "))),
            tt = List.First(List.Select(Titles, each Text.StartsWith(t1, _)), null),
            t2 = if tt = null then t1 else Text.Middle(t1, Text.Length(tt))
        in  Text.Select(t2, Keep),

    NameHit = (a as text, b as text) as logical =>
        let short = if Text.Length(a) <= Text.Length(b) then a else b
        in  a = b or (Text.Length(short) >= o[MinPrefix] and
                      (Text.StartsWith(a, b) or Text.StartsWith(b, a))),

    Check = (r as record) as record =>
        let site    = Record.Field(r, o[SiteCol]),
            src     = if hasSrc then Record.Field(r, o[SourceCol]) else null,
            fromSmt = src = null or Text.StartsWith(Text.From(src), o[SmtSource]),
            base    = if Blank(site) then "หาไซต์ไม่เจอ"
                      else if not fromSmt then "ไซต์ไม่ได้มาจาก SMT" else null,
            sc = Codes(Record.Field(r, o[SapCodeCol])),
            mc = Codes(Record.Field(r, o[SmtCodeCol])),
            sn = NormName(Record.Field(r, o[SapNameCol])),
            mn = NormName(Record.Field(r, o[SmtNameCol]))
        in  [ c = base ?? (if sc = {} then "SAP ไม่มีรหัส" else if mc = {} then "SMT ไม่มีรหัส"
                           else if List.ContainsAny(sc, mc) then "เจอ" else "ไม่เจอ"),
              n = base ?? (if sn = "" then "SAP ไม่มีชื่อ" else if mn = "" then "SMT ไม่มีชื่อ"
                           else if NameHit(sn, mn) then "เจอ" else "ไม่เจอ") ],

    // สรุปรวม 1 คอลัมน์ไว้ทำ slicer: เจอทั้งคู่ · เจอแค่ VendorCode · เจอแค่ VendorName · ไม่เจอทั้งคู่
    //  ไซต์หาไม่เจอ/ไม่ได้มาจาก SMT = ส่งเหตุผลต่อ · ไม่เจอแต่มีฝั่งที่ข้อมูลว่าง = ข้อมูลไม่ครบ
    Summary = (c as text, n as text) as text =>
        if c = "เจอ" and n = "เจอ" then "เจอทั้งคู่"
        else if c = "เจอ" then "เจอแค่ VendorCode"
        else if n = "เจอ" then "เจอแค่ VendorName"
        else if c = "ไม่เจอ" and n = "ไม่เจอ" then "ไม่เจอทั้งคู่"
        else if c = n then c
        else "ข้อมูลไม่ครบ",

    WithChk  = Table.AddColumn(T, "__vendor", each let r = Check(_) in r & [s = Summary(r[c], r[n])]),
    Expanded = Table.ExpandRecordColumn(WithChk, "__vendor", {"c", "n", "s"}, {o[OutCode], o[OutName], o[OutAll]}),
    Typed    = Table.TransformColumnTypes(Expanded,
                   {{o[OutCode], type text}, {o[OutName], type text}, {o[OutAll], type text}})
in
    if _guard then Typed else null   // อ้าง _guard ตรงนี้ ไม่งั้น M ขี้เกียจจะข้ามด่านตรวจไปเลย
