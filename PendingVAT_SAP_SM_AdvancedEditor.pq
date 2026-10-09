// ═══ SAP_SM ของ Pending VAT ฉบับมี Check Vendor (09/10/2026) วางทับทั้งก้อนใน Advanced Editor ═══
// ใช้คู่กับ fnCheckVendor.pq (ต้องสร้าง query fnCheckVendor ก่อน) และ PendingVAT_LatestContract_AdvancedEditor.pq
// ต่างจากฉบับก่อนหน้า 4 จุด: Payload ของ Latest Contract เพิ่ม Vendor Code (SAP) กับ Vendor Name (SAP),
//   step ใหม่ CheckVendor ใต้ ReplaceAllError, และ Added Conditional Column อ้าง CheckVendor แทน ReplaceAllError
// ถ้า SAP_SM ที่ใช้อยู่มี step อื่นที่ไฟล์นี้ไม่มี อย่าวางทับทั้งก้อน ใช้ PendingVAT_SAP_SM_Lookup_snippet.pq แทน
let
    Source = Table.Combine({#"Pending VAT 2025", #"Pending VAT 2026"}),
    ExtractSite = Table.AddColumn(Source, "__site", each
        let r = fnExtractSite([Text Vat Input Pending], "both")
        in [ #"SITE CODE"              = Text.Combine(r[Full], ", "),
             #"SITE CODE NO CANDIDATE" = Text.Combine(r[NoCandidate], ", "),
             SiteCodes = Text.Combine(List.Distinct(r[Full] & r[NoCandidate]), ", ") ]),
    #"Extracted Values" = Table.TransformColumnTypes(
        Table.ExpandRecordColumn(ExtractSite, "__site",
            {"SITE CODE", "SITE CODE NO CANDIDATE", "SiteCodes"}),
        {{"SITE CODE", type text}, {"SITE CODE NO CANDIDATE", type text}, {"SiteCodes", type text}}),
    // ═══ จับคู่รหัสสถานี 2 แหล่งในครั้งเดียว — เจอแหล่งแรกแล้วหยุด (fnMultiSourceFallbackLookup) ═══
    //  ① Latest Contract (SMT) : รหัสสถานี → รหัสสถานีเดิม
    //  ② Site Rental           : Site_ID → WOR_ID   (ทำเฉพาะแถวที่แหล่ง ① ไม่เจอ)
    //  CSType ของ Site Rental = ชื่อย่อบริษัทชุดเดียวกับ Company ของ SMT → map ลงคอลัมน์ Company เดียว
    //  ผลลัพธ์: Matched_Code · Match_Via (ชื่อคอลัมน์ key ที่ชนได้) · Match_Source (มาจาก query ไหน) + payload
    //  เพิ่มแหล่งที่ ③ ในอนาคต = ต่อ record ในลิสต์ ไม่ต้องแก้ step อื่นเลย
    Lookup = fnMultiSourceFallbackLookup(#"Extracted Values", "SiteCodes", {
        [ Name    = "Latest Contract",
          Table   = #"Latest Contract",
          Keys    = {"รหัสสถานี", "รหัสสถานีเดิม"},
          Payload = [ #"SITE OWNER"    = "SITE OWNER",
                      #"ชื่อผู้ให้เช่า" = "ชื่อผู้ให้เช่า",
                      #"สถานะสัญญา"    = "สถานะสัญญา",
                      #"เลขที่สัญญา"    = "เลขที่สัญญา",
                      RegionH        = "GEO_REGION_CODE",
                      Site Type      = "Contract Site Type",
                      Company           = "Company",
                      #"Vendor Code (SAP)" = "Vendor Code (SAP)",
                      #"Vendor Name (SAP)" = "Vendor Name (SAP)" ] ],
        [ Name    = "Site Rental",
          Table   = Site_Rental,
          Keys    = {"Site_ID", "WOR_ID"},
          Payload = [ Company = "CSType",
                       Site Type = "Type",
                #"SITE OWNER"    = "SITE OWNER",
                         ชื่อผู้ให้เช่า = "Lessor_Name"
					 ],                    // ชื่อต่างกัน → ลงคอลัมน์ Company เดียวกัน
          Label   = each "Site Rental - " & [Type] ]           // Match_Source ไดนามิกตามไฟล์ต้นทาง
    }),
    ReplaceAllError = fnReplaceAllError(Lookup),
    CheckVendor = fnCheckVendor(ReplaceAllError),
    #"Added Conditional Column" = Table.AddColumn(CheckVendor, "Sort LastUpdate", each if [LastUpdate] = "Not SM" then 4 else if [LastUpdate] = "Expired" then 3 else if [LastUpdate] = "Pending" then 2 else if [LastUpdate] = "Waiting to released" then 1 else if [LastUpdate] = "Released" then 0 else 999, Int64.Type),
    TRUE = Table.ReplaceValue(#"Added Conditional Column","T","TRUE",Replacer.ReplaceValue,{"Oper"}),
    DTAC = Table.ReplaceValue(TRUE,"D","DTAC",Replacer.ReplaceValue,{"Oper"}),
    #"Site Type" = Table.TransformColumns(
    DTAC,
    {
        {
            "Site Type",
            each
                let
                    v = if _ = null then null else Text.Trim(Text.From(_))
                in
                    if v = null or v = "" then
                        null
                    else if v = "Inbuilding"
                        or v = "WIFI"
                        or Text.StartsWith(v, "IBC") then
                        "IBC"
                    else if v = "Outdoor/Macro"
                        or Text.StartsWith(v, "MACRO") then
                        "MACRO"
                    else if Text.StartsWith(v, "Online-")
                        or Text.StartsWith(v, "ONLINE") then
                        "ONLINE"
                    else
                        v,
            type text
        }
    }
),
    #"Payment Type" = Table.AddColumn(#"Site Type", "Payment Type", each
        let
            s       = Text.Upper(Text.Trim(Text.From([#"Text Vat Input Pending"] ?? ""))),
            chars   = Text.ToList(Text.Start(s, 6)),
            cnt     = List.Count(List.FirstN(chars, each List.Contains({"A".."Z"}, _))),
            hasLead = cnt >= 1 and cnt <= 5 and cnt < List.Count(chars) and List.Contains({".", "-", "/", " "}, chars{cnt}),
            lead    = if hasLead then Text.Start(s, cnt) else ""
        in
            if List.Contains({"E", "ELE"}, lead) or Text.StartsWith(s, "ELECTRICITY") then "Electric"
            else if List.Contains({"SITE", "RENT", "REN"}, lead) or Text.StartsWith(s, "RENTAL") then "Rental"
            else if List.Contains({"SER", "SERV"}, lead) then "Service"
            else if lead = "DEP" then "Deposit"
            else if lead = "TEL" then "Telephone"
            else if Text.StartsWith(s, "LB TAX") then "Land & Building Tax"
            else if not hasLead and Text.Contains(s, "ค่าไฟ") then "Electric"
            else if not hasLead and Text.Contains(s, "ค่าเช่า") then "Rental"
            else if not hasLead and Text.Contains(s, "ค่าบริการ") then "Service"
            else "ไม่ระบุ",
        type text)
in
    #"Payment Type"