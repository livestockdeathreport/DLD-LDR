# ขั้นตอนติดตั้ง (ทำตามลำดับ)

1. **Supabase → SQL Editor**: รันไฟล์ `supabase/001_staff_and_status.sql`
2. **Vercel → Settings → Environment Variables**: เพิ่ม `SESSION_SECRET` = สตริงสุ่มยาว 32 ตัวขึ้นไป
   (สร้างได้ด้วย `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`) แล้ว Redeploy
3. สร้างบัญชีเจ้าหน้าที่ในเครื่องตัวเอง แล้วเอา SQL ที่ได้ไปรันใน Supabase:
   ```
   node scripts/make-staff.js central01 'รหัสผ่านยาวๆ' central "ส่วนกลาง"
   node scripts/make-staff.js ldd-cm 'รหัสผ่านยาวๆ' province "ปศุสัตว์จังหวัดเชียงใหม่" "เชียงใหม่"
   node scripts/make-staff.js ldd-r5 'รหัสผ่านยาวๆ' region "ปศุสัตว์เขต 5" "เชียงใหม่,ลำพูน,ลำปาง,แม่ฮ่องสอน"
   ```
   ชื่อจังหวัดต้องสะกดตรงกับในฟอร์มแจ้งเหตุ (ชุดข้อมูล kongvut เช่น "กรุงเทพมหานคร")
4. วางไฟล์ทับของเดิมใน GitHub (โครงสร้างเหมือนกัน) แล้ว push

## สิทธิ์
| บทบาท | เห็นเบอร์/ชื่อผู้แจ้ง | กดรับงาน/ปิดงาน |
|---|---|---|
| central (ส่วนกลาง) | ทุกจังหวัด | ได้ทุกจังหวัด |
| region (ปศุสัตว์เขต) | จังหวัดในเขต | ไม่ได้ (ดูอย่างเดียว) |
| province (ปศุสัตว์จังหวัด) | จังหวัดตัวเอง | ได้เฉพาะจังหวัดตัวเอง |

ปรับสิทธิ์กดได้ที่ `ACT_ROLES` ใน `lib/auth.js` บรรทัดเดียว
