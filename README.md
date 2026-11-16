# CustomBlocker — Safari Content Blocker với bộ lọc tùy chỉnh (iPhone)

App iOS + Safari Content Blocker extension, cho phép sư huynh tự nhập bộ lọc
chặn quảng cáo theo ý mình, và đăng ký các danh sách lọc có sẵn qua link
(EasyList, uBlock filters, ABPVN…) với cập nhật tự động.

## Cách hoạt động

- App (SwiftUI) quản lý các bộ lọc: một list nhập tay + các list đăng ký qua link.
- App dịch mỗi list thành luật content-blocker của Safari, gộp lại thành
  `blockerList.json`, ghi vào **App Group** `group.ic.thanhbinh.CustomBlocker`.
- Extension đọc file JSON đó và trả cho Safari. Safari tự chặn request
  và ẩn phần tử, không cần app chạy nền.
- Mọi thay đổi (bật/tắt list, thêm list, lưu bộ lọc tay) đều biên dịch lại
  và nạp lại cho Safari ngay (`SFContentBlockerManager.reloadContentBlocker`).

## Đăng ký list qua link (mới v1.1)

Trong app, bấm **Thêm list qua link**, dán link file bộ lọc (vd.
`https://easylist.to/easylist/easylist.txt`). App tải về, dịch sang định
dạng Safari rồi áp dụng. Mỗi list có công tắc bật/tắt riêng; vuốt sang trái
để xóa list đã thêm (list nhập tay "Bộ lọc của tôi" không xóa được).

**Cập nhật tự động:** app kiểm tra cập nhật mỗi 24 giờ khi mở app, và đặt
lịch chạy nền (BGAppRefreshTask) để iOS tự cập nhật — chạy nền là nỗ lực
tốt nhất, iOS có thể hoãn; bấm **Cập nhật tất cả ngay** để chắc chắn.

**List mặc định:** file `App/DefaultLists.txt` (file `block_ads.txt` của
huynh) đính kèm sẵn 10 list: uBlock filters, Badware risks, Privacy,
Quick fixes, Unbreak, EasyList, EasyPrivacy, AdGuard URLhaus, Peter Lowe,
ABPVN, HaGeZi Multi PRO — cộng 2 luật mẫu `/ads.js$script`, `/pagead.js$script`
trong list nhập tay. Lần đầu mở app sẽ tải các list này về (khoảng 20 MB).

## Giới hạn 50.000 luật của Safari

Safari chỉ cho tối đa 50.000 luật trong một bộ lọc. 11 list mặc định dịch
ra hơn 420.000 luật riêng biệt, nên app xử lý như sau:

- Khử trùng lặp giữa các list.
- Whitelist (`@@...`) luôn giữ hết và xếp cuối file.
- Chia đều: mỗi list đang bật được lấy trước 1 phần bằng nhau, còn thừa thì
  lấy tiếp theo thứ tự ưu tiên (list nhập tay trước, rồi tới các list đăng ký).
- App báo rõ số luật đã áp dụng và số luật đã bỏ; tắt bớt danh sách lớn
  (vd. HaGeZi, URLhaus) để đủ chỗ cho các list khác.

File `Blocker/blockerList.json` đi kèm trong project là ảnh chụp (snapshot)
5.000 luật từ các list mặc định — extension dùng nó làm dự phòng trước khi
app chạy lần đầu. App sẽ ghi đè bằng bản đủ 50.000 luật sau khi tải list về.
(Snapshot đi kèm chỉ 5.000 luật vì đẩy file lên GitHub qua API không gửi
được file 6,4 MB — bản đầy đủ 50.000 luật app tự biên dịch lại lúc mở lần đầu.)

## Cú pháp bộ lọc (mỗi dòng 1 luật)

```
# dòng bắt đầu bằng # là ghi chú, bỏ qua
||quangcao.com              chặn mọi request tới domain + subdomain (chỉ third-party)
||quangcao.com/banner       chặn URL có đường dẫn đó (cả first-party)
quangcao.com                giống ||quangcao.com
##.ad-banner               ẩn phần tử có selector đó trên mọi trang
##[id^="google_ads"]       ẩn phần tử theo selector CSS
example.com##.popup-ad      ẩn phần tử chỉ trên example.com
@@||quangcao.com           cho phép lại domain (đứng sau các luật chặn)
```

List đăng ký còn hiểu thêm cú pháp AdBlock/uBlock đầy đủ hơn:

```
! dòng bắt đầu bằng ! là ghi chú (kiểu EasyList)
/ads.js$script             chặn request chứa /ads.js, chỉ loại script
||example.com^$third-party chặn domain, chỉ third-party
||example.com^$image       chặn domain, chỉ loại ảnh
||example.com^$domain=a.com|b.com   chỉ áp dụng khi trang là a.com/b.com
||example.com^$document    chặn cả khi mở thẳng trang đó
0.0.0.0 quangcao.com       dòng kiểu file hosts
/^https:\/\/x\.com\/.*\.js$/  regex thuần (dạng /.../)
```

Một số kiểu **không dịch được** sang định dạng Safari nên app bỏ qua và đếm
lại (số dòng bỏ qua hiện ở từng list): `$redirect`, `$csp`, `$replace`,
`$removeparam`, `$popup`, `$badfilter`, scriptlet `#+js(...)`, ngoại lệ ẩn
`#@#`, selector procedural `:has(...)`/`#?#`, `$to`, `$denyallow`…

Giới hạn của Safari: tối đa 50.000 luật trong file JSON (xem mục trên).
Content blocker chỉ chặn request + ẩn phần tử theo selector CSS — không chặn
theo nội dung chữ trong trang (cái đó là việc của userscript như
OmniElement Toolkit).

## Bật extension sau khi cài

Cài đặt → Safari → Trình chặn nội dung (iOS 17 trở lên: Tiện ích mở rộng)
→ bật **CustomBlocker**. Sau đó mở app, nhập bộ lọc, bấm Lưu & Áp dụng.

## Build ra file IPA

Muội **không biên dịch được IPA trên máy Linux này** (không có Xcode/iOS SDK).
Có 2 đường build:

### Cách A — GitHub Actions (không cần máy Mac, không cần chứng chỉ lúc build)

Repo đã có sẵn workflow `.github/workflows/build-ipa.yml`. Mỗi lần đẩy lên
nhánh `main` (hoặc bấm Run workflow tay), máy macOS của GitHub sẽ build ra
**file IPA chưa ký** (`CustomBlocker-unsigned.ipa`) trong phần Artifacts.
Tải về rồi ký bằng chứng chỉ của huynh qua **ESign / AltStore / Sideloadly**
rồi cài lên iPhone như mọi IPA sideload khác.

### Cách B — Xcode trên máy Mac

Mở `CustomBlocker.xcodeproj`, chọn team của huynh ở Signing & Capabilities
cho cả 2 target (app + Blocker), bấm Run hoặc Product → Archive → Distribute.

## Lưu ý quan trọng: App Groups

App và extension chia sẻ bộ lọc qua App Group
`group.ic.thanhbinh.CustomBlocker`. Muốn tính năng này chạy thì hồ sơ ký
(provisioning profile) của huynh phải có capability **App Groups** với đúng
group ID này:

- Tài khoản Apple Developer trả phí: bật App Groups cho App ID là xong.
- Chứng chỉ mua sẵn: chỉ chạy được nếu App ID của chứng chỉ đó đã bật
  App Groups (hỏi bên bán chứng chỉ).
- **Chứng chỉ doanh nghiệp (trường hợp của huynh):** bật App Groups cho
  App ID dùng để ký, với đúng group `group.ic.thanhbinh.CustomBlocker`,
  rồi ký IPA bằng profile đó — tính năng đầy đủ, kể cả sửa bộ lọc trong app.
- Apple ID miễn phí (AltStore kiểu free): **không dùng được App Groups**.
  Khi đó app sẽ báo lỗi lúc lưu, extension chỉ dùng bộ lọc mặc định đi kèm
  trong `Blocker/blockerList.json`. Muốn đổi bộ lọc thì sửa file đó trong
  project rồi build lại.

## Cấu trúc project

```
CustomBlocker.xcodeproj/     project Xcode (2 target: app + extension)
App/
  CustomBlockerApp.swift     entry point SwiftUI (+ đăng ký cập nhật nền)
  ContentView.swift          giao diện list lọc + nhập tay + thêm list qua link
  FilterEngine.swift         bộ máy dịch text bộ lọc -> luật content-blocker
  FilterStore.swift          quản lý list (manifest, tải qua link, biên dịch, cập nhật nền)
  DefaultLists.txt           10 list mặc định (file block_ads.txt của huynh)
  Info.plist                 + UIBackgroundModes fetch, BGTaskSchedulerPermittedIdentifiers
  CustomBlocker.entitlements App Groups
  Assets.xcassets/           AppIcon (8 PNG tạo lúc build từ scripts/AppIcon-1024.png.b64)
scripts/
  AppIcon-1024.png.b64       icon 1024x1024 dạng base64 (đẩy qua API chỉ gửi được text)
  generate-icons.sh          giải mã + sips tạo đủ 8 cỡ icon trước khi build
Blocker/
  ContentBlockerRequestHandler.swift   extension trả blockerList.json cho Safari
  blockerList.json           snapshot 5.000 luật từ 11 list mặc định (dự phòng)
  Info.plist
  Blocker.entitlements      App Groups
.github/workflows/build-ipa.yml  build IPA chưa ký trên macOS runner
```

## Phiên bản

- v1.1 (16/11/2026): đăng ký list qua link + cập nhật tự động (24h + chạy
  nền), bật/tắt từng list, 10 list mặc định từ file block_ads.txt của huynh,
  bộ dịch ABP/uBlock đầy đủ (modifiers `$script`/`$domain`/…, regex `/.../`,
  hosts-format), khử trùng + chia đều + cap 50.000 luật, snapshot mặc định
  5.000 luật đi kèm. Kiểm chứng trên Linux: dịch 11 list thật ra 486.930
  luật, bỏ qua 6.937 dòng không hỗ trợ (1,4%), 0 url-filter lỗi regex;
  snapshot đi kèm 5.000 luật (bản đầy đủ 50.000 luật app tự biên dịch lại
  lúc mở lần đầu).
- v1.0 (16/11/2026): chặn domain, chặn URL theo đường dẫn, ẩn phần tử theo
  selector, whitelist `@@`. Chỉ nhập tay từng dòng.
