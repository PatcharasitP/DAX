// ═══ ก้อน Lookup ของ SAP_SM ฉบับมี Check Vendor (09/10/2026) ═══
// เลือกตั้งแต่บรรทัด "Lookup = fnMultiSourceFallbackLookup(" ถึง "ReplaceAllError = fnReplaceAllError(Lookup)," แล้ววางทับด้วยก้อนนี้
// แล้วบรรทัดถัดไป #"Added Conditional Column" = Table.AddColumn(ReplaceAllError, ... เปลี่ยน ReplaceAllError เป็น CheckVendor
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
