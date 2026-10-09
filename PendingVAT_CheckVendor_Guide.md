# Check Vendor ใน Pending VAT ไกด์ทำที่ทรู (09/10/2026)

เทียบผู้ขายของแถว SAP (`Vendor/Customer No.`, `Vendor/Customer Name`) กับผู้ขายในสัญญา SMT ของไซต์ที่จับคู่ได้ (`Vendor Code (SAP)`, `Vendor Name (SAP)`)
ได้ 3 คอลัมน์ใหม่ในตาราง SAP_SM: **Check Vendor** (สรุปไว้ทำ slicer), **Check VendorCode**, **Check VendorName**
ใช้เวลาราว 10 นาที แก้ 3 query (สร้างใหม่ 1, แก้ 2)

## ขั้น 0 ก่อนเริ่ม (1 นาที)
- [ ] Save As ไฟล์ Pending VAT เป็นสำเนาก่อน เช่น `Pending VAT_ก่อน CheckVendor.pbix`
- [ ] Home > Transform data เปิด Power Query
- [ ] เช็คว่าไฟล์เป็นรุ่นที่ไกด์นี้ใช้ได้: เปิด Advanced Editor ของ `SAP_SM` กด Ctrl+F หาคำว่า `ReplaceAllError = fnReplaceAllError(Lookup),` ต้องเจอ 1 ที่
  - ถ้าเจอคำว่า `fnCheckVendor` อยู่แล้ว = เคยใส่แล้ว ไม่ต้องทำซ้ำ
  - ถ้าเจอ step ชื่อ `Vendor_Check` = ไฟล์รุ่น v2 ของวันที่ 8 หยุดก่อน ส่งข้อความบอกฟ้า

## ขั้น 1 สร้าง query `fnCheckVendor`
1. Home > New Source > Blank Query
2. คลิกขวา query ใหม่ > Advanced Editor > ลบของเดิมทั้งหมด > วางโค้ดในกล่องท้ายไฟล์นี้ (หัวข้อ โค้ด fnCheckVendor) ทั้งก้อน > Done
3. เปลี่ยนชื่อ query เป็น `fnCheckVendor` (ตัวพิมพ์ตรงเป๊ะ)
- [ ] ต้องเห็นไอคอน fx และช่องให้ใส่พารามิเตอร์ T กับ Options (ไม่ต้องกด Invoke)

## ขั้น 2 แก้ `Latest Contract` (เพิ่ม 2 คอลัมน์ใน SQL 2 จุด)
เปิด Advanced Editor ของ `Latest Contract`

**จุด A** ในก้อน `trimmed AS ( SELECT ...` หาบรรทัดที่ลงท้าย `[Contract Site Type], [Company],` แล้วเพิ่มบรรทัดใหม่ใต้มัน
```sql
        [GEO_REGION_CODE], [Contract Site Type], [Company],
        [Vendor Code (SAP)], [Vendor Name (SAP)],
```
**จุด B** ใน SELECT สุดท้าย (ก่อน `FROM dedup`) ต่อท้าย `DupCount` ด้วยจุลภาค แล้วเพิ่มบรรทัด
```sql
       [GEO_REGION_CODE], [Contract Site Type], [Company], DupCount,
       [Vendor Code (SAP)], [Vendor Name (SAP)]
FROM dedup
```
กด Done ถ้าขึ้นถาม Native Database Query กด Run
- [ ] ตัวอย่างข้อมูลต้องมีคอลัมน์ `Vendor Code (SAP)` และ `Vendor Name (SAP)` ต่อท้าย

## ขั้น 3 แก้ `SAP_SM` (2 จุด)
เปิด Advanced Editor ของ `SAP_SM`

**จุด A** ใน `Lookup = fnMultiSourceFallbackLookup(...)` ก้อนแรก (`Name = "Latest Contract"`) ตรง Payload หาบรรทัด `Company = "Company" ] ],` แล้วแก้เป็น
```m
                      Company           = "Company",
                      #"Vendor Code (SAP)" = "Vendor Code (SAP)",
                      #"Vendor Name (SAP)" = "Vendor Name (SAP)" ] ],
```
(แก้เฉพาะก้อน Latest Contract ก้อน Site Rental ไม่ต้องแตะ)

**จุด B** เพิ่ม step `CheckVendor` ใต้ ReplaceAllError แล้วเปลี่ยน step ถัดไปให้อ้าง CheckVendor แทน
```m
    ReplaceAllError = fnReplaceAllError(Lookup),
    CheckVendor = fnCheckVendor(ReplaceAllError),
    #"Added Conditional Column" = Table.AddColumn(CheckVendor, "Sort LastUpdate", each ...
```
(บรรทัด `#"Added Conditional Column"` เปลี่ยนแค่คำว่า `ReplaceAllError` ในวงเล็บเป็น `CheckVendor` ส่วนที่เหลือเหมือนเดิม)
กด Done
- [ ] ด้านขวา Applied Steps ต้องมี `CheckVendor` อยู่ระหว่าง ReplaceAllError กับ Added Conditional Column
- [ ] ตารางต้องมีคอลัมน์ใหม่ 5 ตัว: Vendor Code (SAP), Vendor Name (SAP), Check VendorCode, Check VendorName, Check Vendor

## ขั้น 4 Close & Apply แล้วตรวจผล
1. Home > Close & Apply รอ refresh (ถ้าถาม Native Database Query กด Run)
2. Ctrl+S
- [ ] ไม่มี error ไม่มีแถบเทา incomplete data
- [ ] สร้างตารางชั่วคราว ใส่ `Check Vendor` กับนับแถว ต้องเห็นค่าเหล่านี้เท่านั้น: เจอทั้งคู่, เจอแค่ VendorCode, เจอแค่ VendorName, ไม่เจอทั้งคู่, ข้อมูลไม่ครบ, ไซต์ไม่ได้มาจาก SMT, หาไซต์ไม่เจอ
- [ ] หยิบแถว `ไม่เจอทั้งคู่` มาดูด้วยตา 3 ถึง 5 แถว เทียบชื่อผู้ขาย SAP กับ SMT ว่าต่างกันจริง (ถ้าเห็นชื่อเดียวกันแต่ขึ้นไม่เจอ ส่งตัวอย่างชื่อทั้งสองฝั่งให้ฟ้า)
- [ ] ผลรวมยอด Pending ทั้งหน้าต้องเท่าก่อนแก้ (สูตรนี้เพิ่มคอลัมน์ ไม่เพิ่มหรือลดแถว)

## ความหมายของค่า
| Check Vendor | ความหมาย |
|---|---|
| เจอทั้งคู่ | รหัสและชื่อผู้ขาย SAP ตรงกับสัญญา SMT |
| เจอแค่ VendorCode | รหัสตรง ชื่อไม่ตรง (มักเป็นชื่อสะกดต่าง หรือเปลี่ยนชื่อบริษัท) |
| เจอแค่ VendorName | ชื่อตรง รหัสไม่ตรง (น่าตรวจ อาจจ่ายผิดรหัสผู้ขาย) |
| ไม่เจอทั้งคู่ | ผู้ขาย SAP คนละรายกับสัญญา ควรตรวจก่อน |
| ข้อมูลไม่ครบ | ฝั่งใดฝั่งหนึ่งว่าง ดูรายละเอียดที่ Check VendorCode กับ Check VendorName |
| ไซต์ไม่ได้มาจาก SMT | ไซต์จับได้จาก Site Rental ไม่มีผู้ขาย SMT ให้เทียบ |
| หาไซต์ไม่เจอ | Matched_Code ว่าง |

กติกาเทียบ: รหัสตัดศูนย์นำหน้า (0006037391 = 6037391) ช่อง SMT ที่มีหลายรหัสคั่นด้วย , ; / เจอตัวใดตัวหนึ่งถือว่าเจอ
ชื่อตัดคำ บริษัท จำกัด มหาชน บจก. บมจ. หจก. CO.,LTD. คำนำหน้าคน และช่องว่างออกก่อน แล้วเทียบเท่ากันหรือขึ้นต้นเหมือนกัน (SAP ตัดชื่อยาวเหลือราว 35 ตัว) และแปลง จํากัด (นิคหิตกับสระอา) เป็น จำกัด ก่อนเทียบ

## ถ้าเจอ error
| ข้อความ | แปลว่า | แก้ |
|---|---|---|
| fnCheckVendor: ไม่พบคอลัมน์: Vendor Code (SAP) ... | ลืมขั้น 2 หรือขั้น 3 จุด A | กลับไปเพิ่มให้ครบทั้งสองที่ |
| The name 'fnCheckVendor' wasn't recognized | ชื่อ query ไม่ตรง | เปลี่ยนชื่อ query ขั้น 1 ให้ตรงตัวพิมพ์ |
| Invalid column name 'Vendor Code (SAP)' | view ใน SQL ใช้ชื่อคอลัมน์ต่าง | เปิด view ดูชื่อจริงแล้วส่งให้ฟ้า |
| The column 'ReplaceAllError' of the table wasn't found หรือ step เพี้ยน | จุด B พิมพ์ไม่ครบ | ดูให้ CheckVendor อ้าง ReplaceAllError และ Added Conditional Column อ้าง CheckVendor |

ทดสอบแล้วบนเครื่องบ้าน: เทสใน Excel Power Query จริง ผ่าน 29 ใน 29 เคส ตัวพังที่จงใจทำให้ผิดแดงตามคาด ส่วนข้อมูลจริงยังไม่ได้ refresh เพราะ SQL ต่อได้เฉพาะเน็ตทรู

## โค้ด fnCheckVendor (วางทั้งก้อนในขั้น 1)
```m
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
```
