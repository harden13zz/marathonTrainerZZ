# Step 0 操作手册 —— 在你只有 Windows + iPhone + Apple Watch 的情况下跑通

> 这份手册只做一件事：**用 30–60 分钟验证「免费 Apple ID 能不能把手表 App 装进你的 Apple Watch」。**
> 验证通过，再往下写业务代码才有意义；验证失败，就要先决定是否申请 $99 的 Apple Developer Program。

---

## 0. 先理解你现在这台机器的角色

| 你有 | 能干什么 | 不能干什么 |
|---|---|---|
| Windows 电脑 | 浏览器、GitHub 网页版、Sideloadly 签名安装 | 编译 Swift、跑 iOS 模拟器 |
| iPhone | 装 App、配对 Watch、健康数据源 | — |
| Apple Watch | 跑 WorkoutSession、实时心率 | — |
| GitHub 账号 | Codespaces 写代码、Actions 跑 macOS 编译 | Codespaces 无法编译 iOS |

**关键结论：编译在 GitHub Actions 的 macOS 机器上完成，签名和安装在你 Windows 上用 Sideloadly 完成。**
所以你**不需要** Mac，也**不需要**往 GitHub Secrets 里塞 Apple ID 证书。

```
        ┌──────────── Windows 浏览器 ────────────┐
        │  GitHub Codespaces 改代码 → push       │
        └────────────────┬───────────────────────┘
                         │
                  GitHub Actions (macos-15)
                  xcodebuild 不签名构建
                         │
              产物 MarathonTrainer-unsigned-ipa
                         │  下载
                         ▼
              Windows 上 Sideloadly
              （用你的免费 Apple ID 签名 + 装到 iPhone）
                         │
                         ▼
            iPhone 安装 → Watch 自动推送 Watch App
```

---

## 1. 建公开仓库 + 推代码

### 1.1 为什么必须是 Public（这一点最关键）

| | 公共仓库 | 私有仓库 |
|---|---|---|
| macOS 构建分钟数 | **免费不限量** | 每月 2000 分钟，且 macOS **按 10 倍扣** |
| 实际可用 | 无限次构建 | 约 **200 分钟 / 月** ≈ 20 次构建 |

一次 iOS + watchOS 编译约 10 分钟，私有仓库扣 100 分钟额度。Step 0 调试期要反复「改 → 推 → 编译」，私人仓库两三天就会耗尽额度，之后整个月都无法构建。

**公开仓库没有任何泄密风险**，因为仓库里只有：Swift 源码、包名 `com.xxx.marathontrainer`（App Store 上也公开可见）、以及 `MT_BUNDLE_PREFIX` 这类仓库变量。

> ⚠️ **唯一要守住的底线**：以后接入大模型 / 天气服务的 **API Key 绝不能写进代码或 plist**，只能存到 App 内的 Keychain（见项目文档 Task 3）。守住这条，公开仓库就安全。

### 1.2 网页建仓库

打开 <https://github.com/new>，只填这几处：

| 字段 | 填什么 |
|---|---|
| **Repository name** | `MarathonTrainer` |
| **Description** | 可不填 |
| **可见性** | 选 **Public** |
| **Add a README file** | ❌ **不要勾** |
| **Add .gitignore** | ❌ **不要勾** |
| **Choose a license** | ❌ **不要勾** |

> 下面三个**一个都不要勾**。勾了任何一个，GitHub 都会生成一个初始 commit，你 push 时就会因为历史不一致被拒绝，还得处理 `--allow-unrelated-histories` 白白增加麻烦。我们要一个完全空的仓库。

点 **Create repository**。

### 1.3 本地 push

```powershell
# 在项目根目录（C:\software\code\pyproject\marathonTrainer）
git init                    # 若已初始化可跳过
git branch -M main
git add .
git commit -m "Step 0: skeleton"

# 让 Windows 凭据管理器记住登录状态，避免每次都要输 token
git config --global credential.helper manager

git remote add origin https://github.com/<你的用户名>/MarathonTrainer.git
git push -u origin main
```

### 1.4 认证：密码栏要填 Token，不是登录密码

`git push` 弹窗要求登录时，**密码栏不能填 GitHub 登录密码**，必须填 Personal Access Token：

1. 打开 <https://github.com/settings/tokens?type=beta>（Fine-grained token）
2. **Generate new token** → 名称随意，过期 90 天
3. **Repository access** → `Only select repositories` → 选 `MarathonTrainer`
4. **Permissions** → `Repository permissions` → **Contents** → **Read and write**
5. 生成后复制那串 `github_pat_...`（**只显示一次**）
6. 回到终端：用户名填 GitHub 用户名，密码栏粘贴 token

**常见 push 失败**：

| 报错 | 原因 | 解决 |
|---|---|---|
| `remote contains work that you do not have locally` | 建仓库时勾了 README / license | `git pull origin main --allow-unrelated-histories` 后解决冲突再 push |
| `Authentication failed` | 密码栏填了登录密码 | 改成 token，见本节 |
| `Repository not found` | 用户名拼错或仓库未创建 | `git remote -v` 确认地址 |

### 1.5 日常怎么改代码（不需要本地 IDE）

**这台 Windows 上不装 IDEA、也不装 VS Code**——Swift 在 Windows 上编译不了，装了也没用，编辑器只会满屏标红 `import SwiftUI`（那是环境没有库，不是代码错了）。

改代码全部在浏览器里：

```
github.com → 你的仓库 → Code 下拉 → Codespaces 标签 → Create codespace on main
```

打开就是网页版 VS Code（左边文件树、中间编辑器、下面终端），跑在微软服务器上。改完在它的终端里 `git commit && git push`，Actions 自动开始编译。

> Codespace 免费额度每月 60 核时（2 核机器约 30 小时）。用完到 <https://github.com/codespaces> 里 **Stop** 掉，别一直开着。

本地真正需要装的软件只有：**Git**（已装）和签名用的 **Sideloadly + 桌面版 iTunes**。

---

## 2. 配置仓库变量（不是 Secret）

`Settings → Secrets and variables → Actions → Variables → New repository variable`

| 名称 | 值 | 说明 |
|---|---|---|
| `MT_BUNDLE_PREFIX` | 例如 `com.zhangsan` | 你的包名前缀，Actions 会把 `com.yourname` 替换成它 |

> 只是包名，公开无所谓。
> **后续如果改 Bundle ID，一定要同步改 Sideloadly 里的 App ID**，两者必须一致，否则签名失败。

---

## 3. 跑第一次构建

推送后自动触发，或手动 `Actions → Build IPA (Step 0 - free Apple ID signing) → Run workflow`。

> ⚠️ **必须先去第 2 节配好 `MT_BUNDLE_PREFIX`**，否则构建会在第一步报错退出。

第一次大概率失败——这一步的目的就是**看编译错误**。常见几类：

| 报错关键字 | 原因 |
|---|---|
| `cannot find 'XXX' in scope` | pbxproj 里漏加了文件，或文件没写 |
| `No such file or directory: .../Info.plist` | 路径大小写 / 位置不对 |
| `error: Signing for "..." requires a development team` | 没加 `CODE_SIGNING_ALLOWED=NO`，检查 workflow |
| `BUILD SUCCEEDED` 但没产物 | `SYMROOT` / `-derivedDataPath` 不一致 |

把日志里 `error:` 那几行贴回来，就能定位。

---

## 4. 下载 IPA

`Actions → 那次成功的 run → 页面底部 Artifacts → MarathonTrainer-unsigned-ipa`

解压得到 `MarathonTrainer.ipa`。

---

## 5. Windows 上安装 Sideloadly

1. 下载 <https://sideloadly.io>（选 Windows 版）
2. 电脑装 **iTunes 非 Microsoft Store 版**（Sideloadly 需要 Apple 设备驱动，Store 版不行）
3. 数据线连 iPhone，手机上点「信任此电脑」
4. Sideloadly 里：
   - **IPA**：选 `MarathonTrainer.ipa`
   - **Apple ID**：你的免费 Apple ID（会走 Apple 的匿名登录，密码只在本机用）
   - **Bundle ID**：改成和 `MT_BUNDLE_PREFIX` 一致，例如 `com.zhangsan.marathontrainer`
     —— 如果提示已存在，就在后面加个后缀改成 `com.zhangsan.marathontrainer2`
5. 点 **Start**，输入 Apple ID 密码（可能还要 App 专用密码）

> **免费账号的限制（这就是 §1.2 说的那条）**
> - 证书 **7 天**过期，过期后 App 打不开，重跑一遍 Sideloadly 即可
> - 最多同时存在 **3 个**自签 App
> - 没有推送、没有真正的后台刷新

---

## 6. Watch App 怎么办？（Step 0 最关键的验证）

Sideloadly 装的是 iPhone 上的 `.app`，Watch App 在 `Payload/MarathonTrainer.app/Watch/` 里。

1. iPhone 打开 **Watch App（系统自带那个）** → 找到 **MarathonTrainer** → 打开「在 Apple Watch 上显示 App」
2. 等手表上的安装圈转完
3. 手表主屏找到 **MT Watch**，点开

### 结果一：手表能打开 → ✅ Step 0 通过，往下写业务代码

### 结果二：手表列表里根本没有这个 App → ⚠️ 免费签名不支持手表 App

这是**已知的高风险点**，Apple 没有官方文档承诺免费账号能装 watchOS App。
应对顺序：

1. 先在手机上确认 App 本身能正常打开（排除 IPA 结构问题）
2. 确认 Watch 和 iPhone 是同一个 Apple ID
3. 试 **AltStore**（<https://altstore.io>，Windows 版需装 AltServer + iCloud）
4. 都不行 → **申请 Apple Developer Program（$99/年）**。这一步越早做越好，因为：
   - 它同时解决证书 7 天过期、3 个 App 上限、后台投递、推送
   - 免费方案下「自动」只能重新定义为「每次打开 App 即自动」，体验会打折

---

## 7. Step 0 验收清单

在手机上：

- [ ] App 打开不闪退，首页能看到 `WatchConnectivity` 一栏
- [ ] 点「申请 HealthKit 权限」能弹出系统授权弹窗（说明 entitlements 签名成功）
- [ ] 输入文字 → 点「发送到手表」

在手表上：

- [ ] **不依赖手机**，单独点开 App 能进去
- [ ] 「来自手机」显示刚才那段文字
- [ ] 点「开始跑步」→ 出现时长 / 心率（心率要等 10–20 秒）
- [ ] 心率有数字跳动（说明 WorkoutSession 拿得到真实数据）
- [ ] 点停止 → 手表「健身」App 里出现这条跑步记录，并同步到 iPhone
- [ ] 点「回执手机」→ 回到 iPhone，列表里出现手表回执

六项里如果**「手表能单独打开」失败**，先停下，按第 6 节处理。
其他项失败基本都是代码问题，贴日志重来。

---

## 8. 日常开发循环（验证通过后）

```
Codespaces 里改 Swift → git push → Actions 自动构建（约 8–15 分钟）
   → 下载 artifact → Sideloadly 重装
```

**每 7 天**重新用 Sideloadly 装一次（证书过期）。可以设个日历提醒。

---

## 9. 接下来做什么

现在可以先不写业务代码，先把 Step 0 跑通。跑通之后按项目文档的 Task 顺序：

1. **Task 3**：设置页（API Key 存 Keychain、固定城市）
2. **Task 2**：HealthKit 读取（HRV / 静息心率 / 睡眠 → 基线）
3. **Task 4**：天气（Open-Meteo，免 Key）
4. **Task 1**：训练计划生成
5. **Task 5**：当日课程自动生成 + 通知
6. **Task 6**：下发到手表 → **Task 7**：手表端训练执行

> 文档 §6 里 Task 6/7（手表）排得比较靠后。既然手表链路是最大风险，建议 **Task 7 提前到 Task 2 之后做**——它就是本项目最独特、也最容易翻车的部分。
