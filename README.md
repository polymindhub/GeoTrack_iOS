# پروژه کامل نیتیو آیفون GeoTrack (Swift / SwiftUI)

این پروژه، نسخه اختصاصی، ۱۰۰٪ نیتیو و بدون وابستگی خارجی **GeoTrack** برای گوشی‌های **iPhone (iOS)** است.

## ۱. ویژگی‌ها و فایل‌ها
- **`AltitudeFilter.swift`**: فیلتر دقیق ضد پرش و جهش ناگهانی ارتفاع (حذف نویزهای چندصد متری GPS آیفون).
- **`KalmanLatLong.swift`**: فیلتر کالمن ۲ بعدی و ۳ بعدی برای مسیر و فواصل دقیق.
- **`LocationManager.swift`**: استفاده از `CoreLocation` و `CLLocationManager` با مجوز ردیابی پس‌زمینه (`UIBackgroundModes: location`).
- **`ContentView.swift`**: رابط کاربری شکیل و مدرن با کارت‌های سرعت، ارتفاع فیلترشده، مسافت و زمان.
- **`GeoTrack.xcodeproj`**: فایل رسمی پروژه Xcode.

---

## ۲. نحوه تولید فایل .ipa در گیت‌هاب اکشن (بدون مک و در کمتر از ۲ دقیقه)

1. پوشه `ios_swift_project` را در یک ریپازیتوری گیت‌هاب قرار دهید.
2. به تب **Actions** بروید.
3. ورک‌فلو **Build iOS App (Swift)** با دستور رسمی اپل (`xcodebuild`) اجرا شده و در انتهای بیلد، فایل **`GeoTrack.ipa`** را در بخش **Artifacts** آماده دانلود قرار می‌دهد!
