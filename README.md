# ainutrition

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


# 🥗 AI 營養素分析 (ainutrition) 專案協作指南

歡迎所有組員！為了確保主程式碼的穩定性，我們將採用嚴格的分支工作流程。

## 👥 第一次設定：複製專案 (Clone)

請使用以下指令將專案下載到您的本地電腦：

```bash
# 請使用 HTTPS 協定複製您的私人專案
git clone https://github.com/pennywong11/ainutrition.git

# 進入專案資料夾
cd ainutrition
````

## 🛠️ 日常開發流程：確保 `main` 分支的穩定

**⚠️ 警告：** **絕對禁止** 在 `main` 分支上直接開發或修改程式碼！

### 步驟 1: 建立新的工作分支 (Branch)

每次開始新功能開發或修復 Bug 之前，請先從 `main` 分支拉取最新程式碼，並建立一個新的分支：

```bash
# 確保您在 main 分支上並同步遠端最新內容
git switch main
git pull

# 建立並切換到新的工作分支
# 請將 [您的分支名稱] 替換為實際的名稱，例如：feat/implement-camera-picker 或 fix/login-bug
git switch -c [您的分支名稱]
```

### 步驟 2: 開發、提交與推送 (Commit & Push)

在您的新分支上進行程式碼修改，並定期提交到您的本地紀錄：

```bash
# 完成修改後，將變動加入暫存區
git add .

# 提交變動
git commit -m "Feat: 實作了食物照片擷取功能" 
# [提示] 請使用簡短清晰的 Commit 訊息
```

然後，將您的工作分支推送到 GitHub 遠端儲存庫：

```bash
# 第一次推送時，設定追蹤遠端分支
git push -u origin [您的分支名稱]
```

### 步驟 3: 請求合併 (Pull Request, PR)

當您確定功能已完成且經過測試時，**請不要自己合併**。您需要在 GitHub 網站上提交 Pull Request (PR)：

1.  進入 GitHub 專案頁面。
2.  點擊 **`Pull requests`** 選項卡。
3.  點擊 **`New pull request`**。
4.  將 **您的分支** 請求合併到 **`main`** 分支。
5.  等待組長或指定的審核人審核並合併。

## 🔒 環境變數 (.env) 安全提示

  * 專案中的 **`.env`** 檔案用於存放機密金鑰，它已被加入 **`.gitignore`** 清單中。
  * **請勿** 提交 `.env` 檔案到 Git。
  * 如果您需要新增環境變數，請在本地 `.env` 中加入，並參考 **`.env.example`** 來了解所有需要的變數。

<!-- end list -->

```
```
