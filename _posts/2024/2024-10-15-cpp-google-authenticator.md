---
layout: post
title:  "[C++] Google Authenticator 算法实现"
categories: c/c++
author: wenfh2020
---

`谷歌验证码` 验证的工作原理是：服务端和客户端双方通过 `共享密钥` 基于 TOTP（Time-based One-Time Password）算法产生的动态验证码进行校验。

密钥是共享的，不是十分安全。但作为二次验证，而且 `共享密钥` 传递的频率非常低，它能有效地提高用户账户的安全性。

> 谷歌验证码算法并不难，C++ 源码资料不多，因为项目需要做了相关功能，这里分享一下对应的实现源码。



* content
{:toc}

---

## 1. 概述

Google Authenticator 使用基于时间的一次性密码 (TOTP, Time-based One-Time Password) 算法来生成动态验证码。它是一种两步验证方法，通常用于增强安全性。

TOTP 工作原理：

* Google Authenticator 使用的 TOTP 是基于时间的动态验证码，每 30 秒生成一个新密码。
* 每个用户会有一个唯一的密钥 (secret key)，这个密钥会用于和当前时间戳结合生成唯一的验证码。
* 每个 TOTP 验证码有时限，通常为 30 秒，当时间超过这个时限，用户需要使用新的验证码。

> 上述文字来源：ChatGPT

---

## 2. 使用逻辑

下图是用户账号登录使用谷歌验证码的逻辑：

1. 用户第一次登录校验用户名和密码成功后，须要使用 App（谷歌身份验证器）扫码获取验证码进行验证。
2. 用户第二次登录校验用户名和密码成功后，不用再扫码，通过 App 查看对应的验证码提交验证。

<div align=center><img src="/images/2024/2024-10-16-08-49-06.png" width="85%" data-action="zoom"></div>

---

## 3. 源码

详细源码请参考 [GitHub](https://github.com/wenfh2020/GoogleAuthenticator)。

### 3.1 接口

```cpp
class GoogleAuthenticator {
public:
    GoogleAuthenticator() {}
    // 生成随机密钥
    std::string GenerateSecret();
    // 设置密钥
    void SetSecret(const std::string& s, bool bNeedEndcode=true);
    // 获取密钥
    std::string GetSecret() const { return m_secret; }
    // 生成验证码
    std::string GenerateCodeForTimeSlice(long timeSlice);
    // 验证验证码（discrepancy 允许误差步长个数）
    bool ValidateCode(const std::string &inputCode, int discrepancy=1, long curTimeSlice=0);
    // 生成二维码 URL
    std::string GetQRCodeURL(const std::string& account, const std::string &title,
        int width = 200, int height = 200, const std::string &level = "M") const;
};
```

---

### 3.2 TOTP 算法

* 生成验证码。通过密钥，基于（本地当前）时间戳生成动态验证码。

```cpp
// 生成验证码
std::string GoogleAuthenticator::GenerateCodeForTimeSlice(long timeSlice) {
    // 30 秒为一个时间步，kTimePeriod 是定义的时间段常量（通常为30秒）
    // 将传入的时间戳除以时间段，得到当前时间步
    long timestamp = timeSlice / kTimePeriod; 

    // 为 Base32 编码的密钥添加填充
    // 将原始密钥进行 Base32 填充，以便进行解码
    auto paddedSecret = AddBase32Padding(m_secret); 

    std::string key;
    // 创建一个字符串以存储解码后的密钥
    // 将填充后的 Base32 密钥解码成字节
    Base32Decode(paddedSecret, key); 

    // 确保计数器以大端序处理
    // 创建一个 8 字节的缓冲区以存储计数器
    unsigned char buf[8];
    // 将时间步编码为大端序的字节流
    EncodeCounterBigEndian(timestamp, buf);

    // 使用 HMAC-SHA1 生成哈希值
    // 使用解码后的密钥和编码的时间戳生成 HMAC-SHA1 哈希
    auto hmacResult = HmacSha1(key, std::string((char*)buf, 8));

    // 动态截断算法 (Dynamic Truncation)
    // 从 HMAC 结果的最后一个字节获取偏移量（最后一个字节的低 4 位）

    // 计算偏移量以确定截取位置
    int offset = hmacResult[hmacResult.size() - 1] & 0x0F;
    // 将 HMAC 中的 4 字节转换为二进制数字
    int binary = ((hmacResult[offset] & 0x7F) << 24) | // 取出偏移量位置的字节并左移
                 ((hmacResult[offset + 1] & 0xFF) << 16) | // 取下一个字节
                 ((hmacResult[offset + 2] & 0xFF) << 8) |  // 取下一个字节
                 (hmacResult[offset + 3] & 0xFF); // 取下一个字节

    // 生成 6 位 OTP
    // 使用取模运算生成 6 位的验证码（范围为 0 到 999999）
    int code = binary % 1000000;

    // 返回填充为 6 位的字符串
    // 创建一个字符串流用于格式化输出
    std::ostringstream oss;
    // 将验证码格式化为 6 位，不足的用 0 填充
    oss << std::setw(6) << std::setfill('0') << code;
    // 返回生成的验证码字符串
    return oss.str();
}
```

* 验证验证码。

```cpp
// 校验验证码是否正确
bool GoogleAuthenticator::ValidateCode(const std::string &inputCode,
    int discrepancy, long curTimeSlice) {
    if (inputCode.length() != 6) {
        return false;
    }

    if (curTimeSlice == 0) {
        curTimeSlice = time(nullptr);
    }

    // 遍历时间漂移范围内的时间片 (-discrepancy 到 +discrepancy)
    for (int i = -discrepancy; i <= discrepancy; ++i) {
        // 使用带有时间片偏移量的时间戳生成验证码
        long timeSlice = curTimeSlice + i * kTimePeriod;
        auto generatedCode = GenerateCodeForTimeSlice(timeSlice);

        // 如果生成的验证码与输入验证码匹配，返回 true
        if (generatedCode == inputCode) {
            return true;
        }
    }

    // 如果在漂移范围内没有找到匹配的验证码，返回 false
    return false;
}
```

---

### 3.3. 测试

* 源码。

```cpp
// g++ -std=c++17 -o t main.cpp GoogleAuthenticator.cpp -lssl -lcrypto && ./t
int main() {
    GoogleAuthenticator ga;

    // 生成随机密钥
    auto secret = ga.GenerateSecret();
    // 设置固定密钥
    // auto secret = "5TE7J7TN4LJGMWPXCXD5CFAKDJJPQT3L";
    ga.SetSecret(secret);
    std::cout << "Old Secret: " << secret << std::endl
              << "New Secret: " << ga.GetSecret() << std::endl;

    // 生成二维码 URL
    auto title = "example";
    auto account = "test";
    auto qrCodeURL = ga.GetQRCodeURL(account, title);

    std::cout << "Title: " << title << std::endl;
    std::cout << "Account: " << account << std::endl;
    std::cout << "QR code url: " << qrCodeURL << std::endl;

    // 生成验证码
    auto code = ga.GenerateCodeForTimeSlice(time(nullptr));
    std::cout << GetNowTime() << ", Current code: " << code << std::endl;

    // 校验验证码
    bool isValid = ga.ValidateCode(code);
    std::cout << (isValid ? "Check code ok!" : "Check code fail!") << std::endl;
    
    int i = 0;
    while (++i <= 30) {
        code = ga.GenerateCodeForTimeSlice(time(nullptr));
        std::cout << GetNowTime() << ", Current code: " << code << std::endl;
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }

    // 校验验证码（测试时间误差）
    std::cout << "Input code to check:" << std::endl;
    std::cin >> code;
    isValid = ga.ValidateCode(code);
    std::cout << GetNowTime() << ", "
              << (isValid ? "Check code ok!" : "Check code fail!")
              << std::endl;
    return 0;
}
```

* 结果。

```shell
# 随机密钥
Old Secret: FLTEWDAQDMTQI2HX3XC5MDTPDULJRT6Z
# 经过 Base32 编码的密钥
New Secret: IZGFIRKXIRAVCRCNKRIUSMSILAZVQQZVJVCFIUCEKVGEUUSUGZNA
# 密钥相关属性信息
Title: example
Account: test
# 生成第三方的二维码图片链接
QR code url: https://api.qrserver.com/v1/create-qr-code/?data=...
# 校验验证码正确
2024-10-15 17:03:44, Current code: 874228
Check code ok!
# 算法根据本地时间 30 秒时间内刷新一次验证码
2024-10-15 17:03:44, Current code: 874228
2024-10-15 17:03:45, Current code: 874228
...
2024-10-15 17:03:58, Current code: 874228
2024-10-15 17:03:59, Current code: 874228
2024-10-15 17:04:00, Current code: 168064
2024-10-15 17:04:01, Current code: 168064
...
2024-10-15 17:04:11, Current code: 168064
2024-10-15 17:04:12, Current code: 168064
2024-10-15 17:04:13, Current code: 168064
# 验证码验证可以根据本地时间容错。
Input code to check:
168064
2024-10-15 17:04:19, Check code ok!
```

---

## 4. 参考

上述 C++ 代码主要参考了 [PHP](https://github.com/PHPGangsta/GoogleAuthenticator/blob/master/PHPGangsta/GoogleAuthenticator.php) 和 Go 语言实现的方案（参考下面代码）。

```go
package main

import (
    "fmt"
    "net/url"
    "time"

    "github.com/pquerna/otp/totp"
)

// 验证 OTP
func verifyCode(inputOTP, secret string) bool {
    return totp.Validate(inputOTP, secret)
}

func getQRCodeGoogleURL(name, secret string, title *string, 
    params map[string]interface{}) string {

    width := 200
    height := 200
    level := "M"

    otpauth := fmt.Sprintf("otpauth://totp/%s?secret=%s",
        url.QueryEscape(name), url.QueryEscape(secret))
    if title != nil {
        otpauth += "&issuer=" + url.QueryEscape(*title)
    }

    return fmt.Sprintf(
        "https://api.qrserver.com/v1/create-qr-code/?data=%s&size=%dx%d&ecc=%s",
        url.QueryEscape(otpauth), width, height, level)
}

// 获取当前 OTP
func getCode(secret string) (string, error) {
    return totp.GenerateCode(secret, time.Now())
}

func main() {
    // 生成密钥
    key, err := totp.Generate(totp.GenerateOpts{
        Issuer:      "YourAppName",
        AccountName: "user@example.com",
        Secret:      []byte("2VZUWYTWHDYTFV7L32NQVMVI2FCJHU6X"),
    })
    if err != nil {
        fmt.Println("Error generating key:", err)
        return
    }

    // 打印密钥和二维码链接
    title := "YourAppName"
    params := map[string]interface{}{
        "width":  200,
        "height": 200,
        "level":  "M",
    }

    qrCodeURL := getQRCodeGoogleURL(key.AccountName(), key.Secret(), &title, params)
    fmt.Printf("Secret: %s\n", key.Secret())
    fmt.Println("QR Code URL:", qrCodeURL)

    // 获取当前 OTP
    for {
        otp, _ := getCode(key.Secret())
        fmt.Printf("Current OTP: %s\n", otp)
        // 等待 1 秒
        time.Sleep(1 * time.Second)
    }
}
```
