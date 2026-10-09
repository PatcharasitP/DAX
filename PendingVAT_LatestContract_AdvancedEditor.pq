// ═══ Latest Contract ของ Pending VAT ฉบับเพิ่ม Vendor Code (SAP) กับ Vendor Name (SAP) (09/10/2026) ═══
// ใช้คู่กับ fnCheckVendor.pq และ PendingVAT_CheckVendor_Guide.md (ขั้น 2)
// ‼️ ก่อนวาง: เปลี่ยน <server> กับ <database> 3 จุดให้เป็นค่าเดิมจากบรรทัด Sql.Database ของ query ที่ใช้อยู่
//    (รีโปนี้เป็นสาธารณะ จึงไม่ใส่ชื่อเซิร์ฟเวอร์กับฐานข้อมูลจริง)
// ต่างจากฉบับ 27/08/2026 แค่ 2 บรรทัด [Vendor Code (SAP)], [Vendor Name (SAP)] ใน trimmed กับ SELECT ล่างสุด
// ═══ Latest Contract — ฉบับดันงานลง SQL (27/08/2026) ═══════════════════════════
// วางทับ M เดิมทั้งหมดใน Advanced Editor ของ query "Latest Contract"
// สิ่งที่หายไปจาก M เดิม (ตั้งใจ — ย้ายไปทำใน SQL หมดแล้ว):
//   NEW / Renamed Columns / ReplaceAllError / OLD / Filtered Rows / Top1PerGroup
// ผลลัพธ์: 10 คอลัมน์ (จากเดิม 118) · 1 แถวต่อ (รหัสสถานี + รหัสสถานีเดิม)
let
    Source = Sql.Database("<server>", "<database>", [Query = "
WITH src AS (
    SELECT *, 1 AS __src FROM <database>.dbo.VW_ContractDetail_True_FullReport
    UNION ALL
    SELECT *, 2 AS __src FROM <database>.dbo.VW_ContractDetail_Dtac_FullReport
),
trimmed AS (
    SELECT
        CASE WHEN UPPER(LEFT([รหัสสถานี], 2)) IN ('D_', 'T_')
             THEN SUBSTRING([รหัสสถานี], 3, 4000) ELSE [รหัสสถานี] END AS [รหัสสถานี],
        CASE WHEN UPPER(LEFT([รหัสสถานี (เดิม)], 2)) IN ('D_', 'T_')
             THEN SUBSTRING([รหัสสถานี (เดิม)], 3, 4000) ELSE [รหัสสถานี (เดิม)] END AS [รหัสสถานีเดิม],
        [SITE OWNER], [ชื่อผู้ให้เช่า], [สถานะสัญญา], [เลขที่สัญญา],
        [GEO_REGION_CODE], [Contract Site Type], [Company],
        [Vendor Code (SAP)], [Vendor Name (SAP)],
        [วันสิ้นสุดสัญญา], [วันเริ่มสัญญา], [Payment Id], [Contract Id], __src
    FROM src
    WHERE LTRIM(RTRIM(ISNULL([สถานะสัญญา], ''))) <> ''
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY [รหัสสถานี], [รหัสสถานีเดิม]
            ORDER BY [วันสิ้นสุดสัญญา] DESC, [วันเริ่มสัญญา] DESC, [Payment Id] DESC,
                     __src ASC, [Contract Id] DESC
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY [รหัสสถานี], [รหัสสถานีเดิม],
                         [วันสิ้นสุดสัญญา], [วันเริ่มสัญญา], [Payment Id]
        ) AS DupCount
    FROM trimmed
),
top1 AS (
    SELECT * FROM ranked WHERE rn = 1
),
dedup AS (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY UPPER(LTRIM(RTRIM([รหัสสถานีเดิม])))
        ORDER BY [รหัสสถานี], [เลขที่สัญญา]
    ) AS rn2
    FROM top1
)
SELECT [รหัสสถานี],
       CASE WHEN rn2 = 1 THEN [รหัสสถานีเดิม] ELSE NULL END AS [รหัสสถานีเดิม],
       [SITE OWNER], [ชื่อผู้ให้เช่า], [สถานะสัญญา], [เลขที่สัญญา],
       [GEO_REGION_CODE], [Contract Site Type], [Company], DupCount,
       [Vendor Code (SAP)], [Vendor Name (SAP)]
FROM dedup
"])
in
    Source